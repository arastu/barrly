import AppKit
import Foundation
import Observation
import os

struct NowPlayingState: Hashable, Sendable {
  var isPlaying: Bool = false
  var title: String = ""
  var artist: String = ""
  var bundleId: String = ""

  /// Web content (Safari / WebKit, Chrome, Firefox, Arc…) reports itself as now playing too.
  static let browserIds = ["com.apple.Safari", "com.apple.WebKit", "com.google.Chrome", "org.mozilla.firefox",
                           "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac", "org.chromium.Chromium"]
  var isBrowser: Bool { Self.browserIds.contains { bundleId.hasPrefix($0) } }
}

/// Now playing, app-agnostic, via the bundled mediaremote-adapter running under /usr/bin/perl
/// (`stream` mode: one process for the life of the app, JSON-line diffs). Falls back to polling
/// Music / Spotify through Apple Events when the adapter is unavailable.
@MainActor @Observable
final class NowPlayingProvider {
  private(set) var state = NowPlayingState()
  private(set) var usingAdapter = false
  @ObservationIgnored private let log = Logger(subsystem: "dev.barrly", category: "nowplaying")
  @ObservationIgnored private var process: Process? = nil
  @ObservationIgnored private var buffer = Data()
  @ObservationIgnored private var payload: [String: Any] = [:]
  @ObservationIgnored private var pollToken: Scheduler.Token? = nil
  @ObservationIgnored private let scheduler: Scheduler
  @ObservationIgnored private var restarts = 0
  @ObservationIgnored private var stopped = false

  init(scheduler: Scheduler) {
    self.scheduler = scheduler
    if let dir = Self.adapterDirectory() { startAdapter(dir) } else { startFallback() }
  }


  /// Resources/MediaRemoteAdapter inside the bundle, MediaRemoteAdapter beside the .app (the Homebrew
  /// layout: outside the bundle so Homebrew's relocation cannot break the app's seal), or the dev build.
  nonisolated static func adapterDirectory() -> URL? {
    var candidates: [URL] = []
    if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("MediaRemoteAdapter")) }
    candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("MediaRemoteAdapter"))
    if let env = ProcessInfo.processInfo.environment["BARRLY_ADAPTER_DIR"] { candidates.append(URL(fileURLWithPath: env)) }
    candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Vendor/build"))
    for c in candidates where FileManager.default.fileExists(atPath: c.appendingPathComponent("mediaremote-adapter.pl").path)
      && FileManager.default.fileExists(atPath: c.appendingPathComponent("MediaRemoteAdapter.framework").path) { return c }
    return nil
  }

  private func startAdapter(_ dir: URL) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    p.arguments = [dir.appendingPathComponent("mediaremote-adapter.pl").path, dir.appendingPathComponent("MediaRemoteAdapter.framework").path,
                   "stream", "--no-artwork", "--debounce=150"]
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      Task { @MainActor [weak self] in self?.consume(d) }
    }
    p.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in self?.adapterExited() } }
    do { try p.run(); process = p; usingAdapter = true; log.info("adapter started pid \(p.processIdentifier)") }
    catch { log.error("adapter failed to start: \(error)"); startFallback() }
  }

  private func adapterExited() {
    guard !stopped else { return }
    restarts += 1
    log.warning("adapter exited (restart #\(self.restarts))")
    process = nil; payload = [:]; publish()
    if restarts > 5 { startFallback(); return }
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(min(30, Double(self?.restarts ?? 1) * 2)))
      guard let self, let dir = Self.adapterDirectory() else { return }
      self.startAdapter(dir)
    }
  }

  private func consume(_ data: Data) {
    guard !data.isEmpty else { return }
    buffer.append(data)
    while let nl = buffer.firstIndex(of: 0x0A) {
      let line = buffer[buffer.startIndex..<nl]; buffer.removeSubrange(buffer.startIndex...nl)
      guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], obj["type"] as? String == "data" else { continue }
      let diff = obj["diff"] as? Bool ?? false
      let p = obj["payload"] as? [String: Any] ?? [:]
      if diff { for (k, v) in p { if v is NSNull { payload[k] = nil } else { payload[k] = v } } } else { payload = p }
      publish()
    }
  }

  private func publish() {
    let s = NowPlayingState(isPlaying: payload["playing"] as? Bool ?? false,
                            title: payload["title"] as? String ?? "", artist: payload["artist"] as? String ?? "",
                            bundleId: payload["parentApplicationBundleIdentifier"] as? String ?? payload["bundleIdentifier"] as? String ?? "")
    if s != state { state = s }
  }

  func stop() {
    stopped = true
    process?.terminate()
    process = nil
  }

  // MARK: - Fallback: Apple Events to Music / Spotify, only while one of them runs.

  private func startFallback() {
    usingAdapter = false
    scheduler.cancel(pollToken)
    pollToken = scheduler.schedule(every: 5) { [weak self] in self?.pollApps() }
  }

  private func pollApps() {
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    for (bundle, name) in [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")] where running.contains(bundle) {
      let src = """
      tell application "\(name)"
        if player state is playing then
          return (name of current track) & "\n" & (artist of current track)
        end if
      end tell
      return ""
      """
      var err: NSDictionary? = nil
      if let out = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !out.isEmpty {
        let parts = out.split(separator: "\n", maxSplits: 1).map(String.init)
        let s = NowPlayingState(isPlaying: true, title: parts.first ?? "", artist: parts.count > 1 ? parts[1] : "", bundleId: bundle)
        if s != state { state = s }
        return
      }
    }
    if state.isPlaying { state = NowPlayingState() }
  }

  func activatePlayer() {
    guard !state.bundleId.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.bundleId) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }
}
