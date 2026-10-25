import AppKit
import Foundation
import Observation
import os

struct AeroWindow: Hashable, Sendable, Decodable {
  var windowId: Int
  var bundleId: String
  var appName: String
  var workspace: String
  enum CodingKeys: String, CodingKey { case windowId = "window-id", bundleId = "app-bundle-id", appName = "app-name", workspace }
}

struct AeroWorkspace: Hashable, Sendable, Identifiable {
  var id: String
  var isFocused: Bool
  var windows: [AeroWindow]
  var bundleIds: [String] { var seen = Set<String>(); return windows.map(\.bundleId).filter { seen.insert($0).inserted } }
}

/// AeroSpace over its socket: initial state by query, then a long-lived `subscribe` stream.
/// All socket I/O happens on a dedicated thread; state is published on the main actor.
@MainActor @Observable
final class AerospaceProvider {
  private(set) var workspaces: [AeroWorkspace] = []
  private(set) var focused: String? = nil
  private(set) var connected = false
  private(set) var events = 0

  @ObservationIgnored private let log = Logger(subsystem: "dev.barrly", category: "aerospace")
  @ObservationIgnored private let query = AerospaceClient()
  @ObservationIgnored private var streamThread: Thread? = nil
  @ObservationIgnored private var stopped = false
  @ObservationIgnored private var refreshTask: Task<Void, Never>? = nil
  @ObservationIgnored private let io = DispatchQueue(label: "dev.barrly.aerospace.query", qos: .userInitiated)

  init() { start() }

  private func start() {
    let t = Thread { [weak self] in self?.streamLoop() }
    t.name = "barrly.aerospace.stream"; t.qualityOfService = .userInitiated
    streamThread = t; t.start()
  }

  /// Runs on the stream thread: connect, subscribe, read events forever, reconnect with backoff.
  nonisolated private func streamLoop() {
    var backoff: TimeInterval = 0.5
    while true {
      let client = AerospaceClient()
      do {
        try client.connect()
        try client.send(["subscribe", "focused-workspace-changed", "focus-changed", "window-detected", "focused-monitor-changed"])
        Task { @MainActor [weak self] in self?.connected = true; self?.refreshNow() }
        backoff = 0.5
        while true {
          let ev = try client.readJSON()
          if ev["exitCode"] != nil { throw AerospaceClient.ClientError.eof } // error reply instead of a stream
          Task { @MainActor [weak self] in self?.handleEvent(ev) }
        }
      } catch {
        client.disconnect()
        Task { @MainActor [weak self] in self?.connected = false }
        Thread.sleep(forTimeInterval: backoff); backoff = min(8, backoff * 2)
      }
    }
  }

  private func handleEvent(_ ev: [String: Any]) {
    events += 1
    if let ws = ev["workspace"] as? String, (ev["_event"] as? String) == "focused-workspace-changed" { focused = ws }
    scheduleRefresh()
  }

  /// Coalesces bursts of events into one query round-trip.
  func scheduleRefresh(delay: Duration = .milliseconds(40)) {
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.refreshNow()
    }
  }

  func refreshNow() {
    io.async { [query, weak self] in
      do {
        if !query.isConnected { try query.connect() }
        let ws = try query.request(["list-workspaces", "--all", "--json"])
        let focusedReply = try query.request(["list-workspaces", "--focused"])
        let win = try query.request(["list-windows", "--all", "--json", "--format", "%{window-id} %{app-bundle-id} %{app-name} %{workspace}"])
        let ids = ((try? JSONSerialization.jsonObject(with: Data(ws.stdout.utf8))) as? [[String: Any]])?.compactMap { $0["workspace"] as? String } ?? []
        let windows = (try? JSONDecoder().decode([AeroWindow].self, from: Data(win.stdout.utf8))) ?? []
        let focused = focusedReply.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = ids.map { id in AeroWorkspace(id: id, isFocused: id == focused, windows: windows.filter { $0.workspace == id }) }
        Task { @MainActor [weak self] in
          guard let self else { return }
          if result != self.workspaces { self.workspaces = result }
          self.focused = focused.isEmpty ? nil : focused
        }
      } catch {
        query.disconnect()
        Task { @MainActor [weak self] in self?.log.warning("query failed: \(String(describing: error))") }
      }
    }
  }

  func focus(workspace id: String) {
    io.async { [query] in
      if !query.isConnected { try? query.connect() }
      _ = try? query.request(["workspace", id])
    }
  }
}
