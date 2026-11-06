import AppKit
import Foundation
import Observation
import os

/// One Rex session and the strongest status a program in it has reported (the OSC 7501 protocol).
struct RexSession: Hashable, Sendable, Identifiable {
  enum State: String, Sendable, Comparable {
    case idle, done, working, error, blocked
    var rank: Int { switch self { case .idle: 0; case .done: 1; case .working: 2; case .error: 3; case .blocked: 4 } }
    static func < (a: State, b: State) -> Bool { a.rank < b.rank }
  }
  var id: String
  var label: String
  var blocks: Int
  var state: State
  var app: String? = nil
  var msg: String? = nil
  var kind: String? = nil
  var needsAttention: Bool { state == .blocked || state == .error }
}

struct RexState: Hashable, Sendable {
  var connected = false
  var sessions: [RexSession] = []
  /// Sessions waiting on the user or failed, strongest state first.
  var attention: [RexSession] { sessions.filter(\.needsAttention).sorted { $0.state > $1.state } }
}

/// Rex sessions and program status, streamed through the `rex` CLI. A Lua watcher (`rex do … --all`)
/// prints one JSON line whenever a session is created, renamed or destroyed, a pane opens or closes, or
/// a program reports its status (working, blocked, done, error). The watcher is restarted with backoff
/// and as soon as Rex launches; while it is down the widget hides.
@MainActor @Observable
final class RexProvider {
  nonisolated static let bundleID = "com.superlogical.rex"
  private(set) var state = RexState()
  private(set) var lastError: String? = nil
  let cliPath: String?

  @ObservationIgnored private let log = Logger(subsystem: "dev.barrly", category: "rex")
  @ObservationIgnored private var process: Process? = nil
  @ObservationIgnored private var buffer = Data()
  @ObservationIgnored private var stderr = Data()
  @ObservationIgnored private var restarts = 0
  @ObservationIgnored private var stopped = false
  @ObservationIgnored private var restartTask: Task<Void, Never>? = nil
  @ObservationIgnored private var tokens: [NSObjectProtocol] = []
  @ObservationIgnored private let io = DispatchQueue(label: "dev.barrly.rex", qos: .userInitiated)

  init() {
    cliPath = Self.findCLI()
    let nc = NSWorkspace.shared.notificationCenter
    tokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
      let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
      guard bid == Self.bundleID else { return }
      Task { @MainActor [weak self] in self?.scheduleRestart(after: 1.5) }
    })
    start()
  }

  /// The CLI inside the server Rex.app installs, or a copy on the usual paths. `BARRLY_REX_CLI` overrides.
  nonisolated static func findCLI() -> String? {
    var candidates: [String] = []
    if let env = ProcessInfo.processInfo.environment["BARRLY_REX_CLI"] { candidates.append(env) }
    candidates.append(NSHomeDirectory() + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")
    candidates += ["/opt/homebrew/bin/rex", "/usr/local/bin/rex"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// The watcher script, kept under Application Support so `rex do` can read it by path.
  nonisolated static func scriptURL() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("Barrly", isDirectory: true)
    let url = dir.appendingPathComponent("rex-status.lua")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      if (try? String(contentsOf: url, encoding: .utf8)) != script { try script.write(to: url, atomically: true, encoding: .utf8) }
      return url
    } catch { return nil }
  }

  private func start() {
    guard !stopped, process == nil, let cli = cliPath else { return }
    guard let script = Self.scriptURL() else { lastError = "could not write the watcher script"; return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cli)
    p.arguments = ["--autostart=false", "do", script.path, "--all"]
    // The watcher hears every session, not the one Barrly happened to be launched from.
    var env = ProcessInfo.processInfo.environment
    for key in ["REX_SESSION", "REX_BLOCK", "REX_CLIENT"] { env[key] = nil }
    p.environment = env
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
    out.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      if d.isEmpty { h.readabilityHandler = nil; return }
      Task { @MainActor [weak self] in self?.consume(d) }
    }
    err.fileHandleForReading.readabilityHandler = { [weak self] h in
      let d = h.availableData
      if d.isEmpty { h.readabilityHandler = nil; return }
      Task { @MainActor [weak self] in self?.stderr.append(d) }
    }
    p.terminationHandler = { [weak self] p in
      let code = p.terminationStatus
      Task { @MainActor [weak self] in self?.exited(code) }
    }
    buffer = Data(); stderr = Data()
    do { try p.run(); process = p; log.info("watcher started pid \(p.processIdentifier)") }
    catch { lastError = "\(error)"; log.error("watcher failed to start: \(error)"); scheduleRestart(after: 10) }
  }

  private func consume(_ data: Data) {
    buffer.append(data)
    while let nl = buffer.firstIndex(of: 0x0A) {
      let line = buffer[buffer.startIndex..<nl]; buffer.removeSubrange(buffer.startIndex...nl)
      guard let sessions = Self.parse(line) else { continue }
      restarts = 0; lastError = nil
      let s = RexState(connected: true, sessions: sessions)
      if s != state { state = s }
    }
  }

  /// One line from the watcher: `{"sessions":[{"id","label","blocks","state","app"?,"msg"?,"kind"?}, …]}`.
  /// Anything else (the watcher's own chatter, an error line) is ignored. An unknown state reads as idle.
  nonisolated static func parse(_ line: Data) -> [RexSession]? {
    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let list = obj["sessions"] as? [[String: Any]] else { return nil }
    return list.compactMap { s in
      guard let id = s["id"] as? String else { return nil }
      return RexSession(id: id, label: s["label"] as? String ?? id, blocks: s["blocks"] as? Int ?? 0,
                        state: (s["state"] as? String).flatMap(RexSession.State.init(rawValue:)) ?? .idle,
                        app: s["app"] as? String, msg: s["msg"] as? String, kind: s["kind"] as? String)
    }
  }

  private func exited(_ code: Int32) {
    process = nil
    if state != RexState() { state = RexState() }
    guard !stopped else { return }
    restarts += 1
    let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if let last = message.split(separator: "\n").last { lastError = String(last) }
    log.warning("watcher exited \(code) (restart #\(self.restarts)): \(message)")
    scheduleRestart(after: min(30, Double(restarts) * 3))
  }

  private func scheduleRestart(after seconds: Double) {
    restartTask?.cancel()
    restartTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      self?.start()
    }
  }

  /// Start the watcher again if it is down (Apple menu click).
  func refreshNow() { if process == nil { restartTask?.cancel(); start() } }

  func stop() { stopped = true; restartTask?.cancel(); process?.terminate(); process = nil }

  /// Bring Rex to the front. No shell involved.
  func activate() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  /// Bring Rex to the front on a session. The app performs `session.select` only while Remote Control
  /// is on in its settings (Rex Server › Client Info).
  func select(_ session: RexSession) {
    activate()
    run(["do", "session.select", "session_id=\(session.id)"])
  }

  private func run(_ args: [String]) {
    guard let cli = cliPath else { return }
    io.async { [log] in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: cli); p.arguments = ["--autostart=false"] + args
      p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
      do { try p.run(); p.waitUntilExit() } catch { log.warning("rex \(args.joined(separator: " ")) failed: \(error)") }
    }
  }

  /// Runs inside Rex's Lua (`rex do SCRIPT --all`): on every relevant event, and every 30 s, it lists the
  /// sessions, their terminal panes and the strongest program status each one reports, as one JSON line.
  nonisolated static let script = """
  -- Barrly's Rex watcher. Prints one JSON line per change: every session with the strongest
  -- program status its terminals report (OSC 7501: idle < done < working < error < blocked).
  local terminal = "com.superlogical.terminal"
  local rank = { idle = 0, done = 1, working = 2, error = 3, blocked = 4 }

  local function snapshot()
    local list, err = rex.call("session.list")
    if not list then return nil, err end
    local out = {}
    for _, s in ipairs(list.sessions or {}) do
      local entry = { id = s.session_id, label = s.label, state = "idle", blocks = 0 }
      local blocks = rex.call("session.list_blocks", { session_id = s.session_id })
      for _, b in ipairs(blocks and blocks.blocks or {}) do
        if b.creator_name == terminal then
          entry.blocks = entry.blocks + 1
          local st = rex.call(terminal .. ".program_status", { session_id = s.session_id, block_id = b.block_id, args = {} })
          for _, r in ipairs(st and st.records or {}) do
            if (rank[r.state] or 0) > rank[entry.state] then
              entry.state = r.state
              entry.app = r.effective_app or r.app
              entry.msg = r.msg
              entry.kind = r.kind
            end
          end
        end
      end
      out[#out + 1] = entry
    end
    return out
  end

  local pending = false
  local function emit()
    pending = false
    local sessions, err = snapshot()
    if not sessions then print(rex.json.encode({ error = err })) return end
    print(rex.json.encode({ sessions = sessions }))
    io.stdout:flush()
  end

  local function schedule()
    if pending then return end
    pending = true
    rex.after(0.15, emit)
  end

  for _, name in ipairs({
    "session_created", "session_destroyed", "session_label_changed",
    "block_created", "block_closed",
    "terminal.program_status_changed", "terminal.program_status_removed",
    "client_joined", "client_left",
  }) do
    rex.on(name, function() schedule() end)
  end

  rex.every(30, function() schedule() end)
  rex.after(0, emit)

  """
}
