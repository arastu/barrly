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
  /// Terminals running an agent (Claude Code, Codex, …), and how many of them are busy or waiting.
  var agents: Int = 0
  var working: Int = 0
  var blocked: Int = 0
  /// The agent programs (Claude Code, Codex, …) running in the session's panes, strongest status first.
  var programs: [RexProgram] = []
  /// Every terminal pane, with its foreground process, in the session's order.
  var panes: [RexPane] = []
  var needsAttention: Bool { state == .blocked || state == .error }
}

/// One terminal pane: what runs in its foreground, and the strongest status any program in it reports.
struct RexPane: Hashable, Sendable, Identifiable {
  var id: String { block }
  var block: String
  var window: String? = nil
  var label: String? = nil
  /// The foreground process (zsh, nvim, claude, cargo, …) and its working directory.
  var name: String? = nil
  var cwd: String? = nil
  var pid: Int? = nil
  var state: RexSession.State = .idle
  var app: String? = nil
  var kind: String? = nil
  var msg: String? = nil
  /// When the status was last reported, for "Idle 2h".
  var updatedAt: Date? = nil
  /// The terminal title and the process that set it (a shell's prompt title, Claude Code's task).
  var title: String? = nil
  var titlePid: Int? = nil
}

/// One agent running in a Rex pane and the status it last reported.
struct RexProgram: Hashable, Sendable, Identifiable {
  var id: String { block }
  var block: String
  var app: String
  var state: RexSession.State
  var kind: String? = nil
  var msg: String? = nil
  /// The window the pane is in, for `session.select`.
  var window: String? = nil
  /// The process that reported the status, and the pane's foreground process (they differ when an
  /// agent reports through a parent process); both are how a Claude Code session is matched to its pane.
  var pid: Int? = nil
  var foregroundPid: Int? = nil
}

struct RexState: Hashable, Sendable {
  var connected = false
  var sessions: [RexSession] = []
  /// Sessions waiting on the user or failed, strongest state first.
  var attention: [RexSession] { sessions.filter(\.needsAttention).sorted { $0.state > $1.state } }
  /// Agents across every session, and how many are busy or waiting on the user.
  var agents: Int { sessions.reduce(0) { $0 + $1.agents } }
  var working: Int { sessions.reduce(0) { $0 + $1.working } }
  var blocked: Int { sessions.reduce(0) { $0 + $1.blocked } }
  /// Every running instance of one agent, with its session, strongest status first.
  func programs(app: String) -> [(session: RexSession, program: RexProgram)] {
    sessions.flatMap { s in s.programs.filter { $0.app == app }.map { (s, $0) } }.sorted { $0.program.state > $1.program.state }
  }
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

  /// One line from the watcher: `{"sessions":[{"id","label","blocks","state","app"?,"msg"?,"kind"?,
  /// "agents"?,"working"?,"blocked"?,"programs"?:[{"block","app","state","kind"?,"msg"?,"window"?,"pid"?,"fg"?}],
  /// "panes"?:[{"block","window"?,"label"?,"name"?,"cwd"?,"pid"?,"state"?,"app"?,"kind"?,"msg"?}]}, …],"summary":{…}}`.
  /// The summary is derived here, so it is ignored.
  /// Anything else (the watcher's own chatter, an error line) is ignored. An unknown state reads as idle.
  nonisolated static func parse(_ line: Data) -> [RexSession]? {
    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let list = obj["sessions"] as? [[String: Any]] else { return nil }
    return list.compactMap { s in
      guard let id = s["id"] as? String else { return nil }
      return RexSession(id: id, label: s["label"] as? String ?? id, blocks: s["blocks"] as? Int ?? 0,
                        state: (s["state"] as? String).flatMap(RexSession.State.init(rawValue:)) ?? .idle,
                        app: s["app"] as? String, msg: s["msg"] as? String, kind: s["kind"] as? String,
                        agents: s["agents"] as? Int ?? 0, working: s["working"] as? Int ?? 0, blocked: s["blocked"] as? Int ?? 0,
                        programs: ((s["programs"] as? [[String: Any]]) ?? []).compactMap { p in
                          guard let block = p["block"] as? String, let app = p["app"] as? String else { return nil }
                          return RexProgram(block: block, app: app,
                                            state: (p["state"] as? String).flatMap(RexSession.State.init(rawValue:)) ?? .idle,
                                            kind: p["kind"] as? String, msg: p["msg"] as? String, window: p["window"] as? String,
                                            pid: p["pid"] as? Int, foregroundPid: p["fg"] as? Int)
                        }.sorted { $0.state > $1.state },
                        panes: ((s["panes"] as? [[String: Any]]) ?? []).compactMap { p in
                          guard let block = p["block"] as? String else { return nil }
                          return RexPane(block: block, window: p["window"] as? String, label: p["label"] as? String,
                                         name: p["name"] as? String, cwd: p["cwd"] as? String, pid: p["pid"] as? Int,
                                         state: (p["state"] as? String).flatMap(RexSession.State.init(rawValue:)) ?? .idle,
                                         app: p["app"] as? String, kind: p["kind"] as? String, msg: p["msg"] as? String,
                                         updatedAt: (p["updated"] as? String).flatMap(parseDate), title: p["title"] as? String,
                                         titlePid: p["title_pid"] as? Int)
                        })
    }
  }

  /// Rex's timestamps: ISO 8601 with any number of fractional digits and a zone offset.
  nonisolated static func parseDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // The formatter wants exactly three fractional digits.
    var t = s
    if let dot = t.firstIndex(of: "."), let end = t[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
      let frac = String(t[t.index(after: dot)..<end])
      t.replaceSubrange(dot..<end, with: "." + (frac + "000").prefix(3))
    }
    if let d = f.date(from: t) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: t)
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

  /// Bring Rex to the front on the pane a program runs in.
  func select(_ program: RexProgram, in session: RexSession) {
    select(block: program.block, window: program.window, in: session.id)
  }

  /// Bring Rex to the front on a session, its window and (when given) the pane.
  func select(block: String?, window: String?, in sessionID: String) {
    if let block { run(["focus", "-s", sessionID, block]) }
    var args = ["do", "session.select", "session_id=\(sessionID)"]
    if let window { args.append("window_id=\(window)") }
    run(args)
    activate()
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

  /// Runs the CLI for its output (`rex ls --json`, `rex window new --json`, …).
  func call(_ args: [String]) async -> Subprocess.Result {
    guard let cli = cliPath else { return Subprocess.Result(ok: false, stdout: Data(), stderr: "the rex command was not found") }
    return await Subprocess.run(cli, ["--autostart=false"] + args)
  }

  /// Runs inside Rex's Lua (`rex do SCRIPT --all`): on every relevant event, and every 30 s, it lists the
  /// sessions, their terminal panes and the strongest program status each one reports, as one JSON line.
  nonisolated static let script = """
  -- Barrly's Rex watcher. Prints one JSON line per change: every session with the strongest
  -- program status its terminals report (OSC 7501: idle < done < working < error < blocked),
  -- its agent panes, and every pane with its foreground process.
  local terminal = "com.superlogical.terminal"
  local rank = { idle = 0, done = 1, working = 2, error = 3, blocked = 4 }

  -- Programs that count as agents for the per-session and total counts, and are listed per pane
  -- under `programs` (block, app, state, kind, msg) so a widget can follow one agent, like Claude Code.
  local agents = { ["claude-code"] = true, codex = true, opencode = true, gemini = true, aider = true }

  local function snapshot()
    local list, err = rex.call("session.list")
    if not list then return nil, err end
    local out = {}
    local summary = { sessions = 0, agents = 0, working = 0, blocked = 0 }
    for _, s in ipairs(list.sessions or {}) do
      -- agents/working/blocked count the terminals in the session running an agent, and
      -- how many of those are busy or waiting on the user.
      local entry = { id = s.session_id, label = s.label, state = "idle", blocks = 0, agents = 0, working = 0, blocked = 0, programs = {}, panes = {} }
      local blocks = rex.call("session.list_blocks", { session_id = s.session_id })
      for _, b in ipairs(blocks and blocks.blocks or {}) do
        if b.creator_name == terminal then
          entry.blocks = entry.blocks + 1
          local st = rex.call(terminal .. ".program_status", { session_id = s.session_id, block_id = b.block_id, args = {} })
          -- The pane's foreground process: how a Claude Code session is matched to its pane.
          local proc = rex.call(terminal .. ".process", { session_id = s.session_id, block_id = b.block_id, args = {} })
          local fg = proc and proc.foreground or nil
          local fgpid = fg and fg.pid or nil
          -- Every pane is listed with its foreground process, for the Rex widget's session list.
          local title = rex.call(terminal .. ".title", { session_id = s.session_id, block_id = b.block_id, args = {} })
          local pane = { block = b.block_id, window = b.window_id, label = b.label, pid = fgpid,
                         name = fg and fg.name or nil, cwd = fg and fg.cwd or nil, state = "idle",
                         title = title and title.title or nil, title_pid = title and title.owner and title.owner.pid or nil }
          entry.panes[#entry.panes + 1] = pane
          local strongest, is_agent, prog = "idle", false, nil
          for _, r in ipairs(st and st.records or {}) do
            local app = r.effective_app or r.app
            -- The pane carries the strongest status any program in it reports, agent or not; an idle
            -- record still counts (it says which program is idle, and since when).
            if not pane.app or (rank[r.state] or 0) > (rank[pane.state] or 0) then
              pane.state = r.state; pane.app = app; pane.kind = r.kind; pane.msg = r.msg; pane.updated = r.updated_at
            end
            if app and agents[app] then
              is_agent = true
              -- One record per pane: the strongest status an agent in it reports.
              if not prog or (rank[r.state] or 0) > (rank[prog.state] or 0) then
                prog = { block = b.block_id, window = b.window_id, app = app, state = r.state or "idle", kind = r.kind, msg = r.msg,
                         pid = r.owner and r.owner.pid or nil, fg = fgpid }
              end
            end
            if (rank[r.state] or 0) > (rank[strongest] or 0) then strongest = r.state end
            if (rank[r.state] or 0) > rank[entry.state] then
              entry.state = r.state
              entry.app = app
              entry.msg = r.msg
              entry.kind = r.kind
            end
          end
          if is_agent then
            entry.programs[#entry.programs + 1] = prog
            entry.agents = entry.agents + 1
            if strongest == "working" then entry.working = entry.working + 1 end
            if strongest == "blocked" then entry.blocked = entry.blocked + 1 end
          elseif fg and fg.name == "claude" then
            -- Claude Code that has not reported a status yet (an attach that just started): listed so
            -- the Claude Code widget can find the pane, but not counted as an agent.
            entry.programs[#entry.programs + 1] = { block = b.block_id, window = b.window_id, app = "claude-code", state = "idle", pid = fgpid, fg = fgpid }
          end
        end
      end
      summary.sessions = summary.sessions + 1
      summary.agents = summary.agents + entry.agents
      summary.working = summary.working + entry.working
      summary.blocked = summary.blocked + entry.blocked
      out[#out + 1] = entry
    end
    return out, nil, summary
  end

  local pending = false
  local function emit()
    pending = false
    local sessions, err, summary = snapshot()
    if not sessions then print(rex.json.encode({ error = err })) return end
    print(rex.json.encode({ sessions = sessions, summary = summary }))
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
    "terminal.program_status_changed", "terminal.program_status_removed", "terminal.process_changed",
    "client_joined", "client_left",
  }) do
    rex.on(name, function() schedule() end)
  end

  rex.every(30, function() schedule() end)
  rex.after(0, emit)
  """
}
