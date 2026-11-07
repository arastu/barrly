import AppKit
import Foundation
import Observation
import os

// Every Claude Code session on the Mac, grouped the way the `claude agents` view groups them, with
// the pane it runs in when it is in Rex. After Tea (github.com/ianiv/tea).
//
// Sources, read every few seconds:
//   - `claude agents --json --all`           the session list
//   - ~/.claude/sessions/<pid>.json          raw live status, and the entrypoint (Agent SDK sessions are hidden)
//   - ~/.claude/jobs/<id>/state.json         background job state, tempo, summary, linked PRs
//   - ~/.claude/gh-pr-status-cache.json      PR state, checks and review, which Claude maintains
//   - the Rex watcher (RexProvider)          panes running Claude, their foreground process and program status,
//                                            the only source that knows a session is waiting on a permission
// These are other programs' internal formats, parsed loosely: a missing field degrades the row.

/// The `claude agents` view's groups, in its order, with `idle` (interactive sessions with no
/// background job, which that view doesn't group) before Completed.
enum ClaudeGroup: Int, CaseIterable, Identifiable, Sendable {
  case review, blocked, working, idle, done
  var id: Int { rawValue }

  var title: String {
    switch self {
    case .review: "Ready for review"
    case .blocked: "Needs input"
    case .working: "Working"
    case .done: "Completed"
    case .idle: "Idle"
    }
  }

  var token: AccentToken? {
    switch self {
    case .review: .mauve
    case .blocked: .peach
    case .working: .blue
    case .done: .green
    case .idle: nil
    }
  }
}

/// What a session is doing right now.
enum ClaudeActivity: Hashable, Sendable {
  case working, shell, waiting(String), idle, failed, stopped, done

  var label: String {
    switch self {
    case .working: "Working"
    case .shell: "Running a shell"
    case .waiting(let why): why
    case .idle: "Idle"
    case .failed: "Failed"
    case .stopped: "Stopped"
    case .done: "Done"
    }
  }

  var symbol: String {
    switch self {
    case .working: "circle.dotted.circle"
    case .shell: "terminal"
    case .waiting: "exclamationmark.circle.fill"
    case .idle: "circle"
    case .failed: "xmark.octagon.fill"
    case .stopped: "stop.circle"
    case .done: "checkmark.circle.fill"
    }
  }

  var token: AccentToken? {
    switch self {
    case .working: .blue
    case .shell: .teal
    case .waiting: .peach
    case .idle, .stopped: nil
    case .failed: .red
    case .done: .green
    }
  }
}

/// One entry of `claude agents --json --all`.
struct ClaudeAgent: Hashable, Sendable {
  var pid: Int?
  var id: String?
  var sessionId: String
  var name: String
  var cwd: String
  var kind: String
  var startedAt: Date
  /// busy / shell / waiting / idle from the session file, which `claude agents --json` reports less
  /// precisely ("shell" comes out as "busy"); nil for a session without a live process.
  var liveStatus: String?

  /// `sessionFile` is ~/.claude/sessions/<pid>.json when the session has one. Returns nil for an
  /// Agent SDK session (entrypoint "sdk-cli" etc.): other apps' sessions aren't yours to open.
  init?(_ d: [String: Any], sessionFile: [String: Any]?) {
    guard let sessionId = d["sessionId"] as? String else { return nil }
    self.sessionId = sessionId
    pid = d["pid"] as? Int
    id = d["id"] as? String
    name = (d["name"] as? String) ?? (d["id"] as? String) ?? sessionId
    cwd = (d["cwd"] as? String) ?? ""
    kind = (d["kind"] as? String) ?? "interactive"
    startedAt = Date(timeIntervalSince1970: ((d["startedAt"] as? Double) ?? 0) / 1000)
    let reported = d["status"] as? String
    let session = sessionFile?["sessionId"] as? String == sessionId ? sessionFile : nil
    if (session?["entrypoint"] as? String)?.hasPrefix("sdk") == true { return nil }
    liveStatus = reported == nil ? nil : (session?["status"] as? String) ?? reported
  }
}

/// ~/.claude/jobs/<id>/state.json
struct ClaudeJob: Hashable, Sendable {
  var state: String?
  var tempo: String?
  var detail: String
  var prURLs: [String]
  var recurring: Bool

  init(_ d: [String: Any]) {
    state = d["state"] as? String
    tempo = d["tempo"] as? String
    detail = (d["detail"] as? String) ?? ""
    prURLs = (d["children"] as? [[String: Any]] ?? []).filter { $0["kind"] as? String == "pr" }.compactMap { $0["href"] as? String }
    let kinds = (d["inFlight"] as? [String: Any])?["kinds"] as? [String] ?? []
    func loop(_ s: Any?) -> Bool { (s as? String)?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("/loop") ?? false }
    recurring = d["routine"] != nil || d["selfWake"] as? Bool == true || kinds.contains("session_cron") || loop(d["intent"]) || loop(d["initialPrompt"])
  }

  /// success / failure / stopped once the job has settled. A recurring job that finished a run isn't done.
  var terminal: String? {
    let mapped: String? = switch state { case "done": "success"; case "failed": "failure"; case "stopped": "stopped"; default: nil }
    guard let mapped, tempo != "active", !(mapped == "success" && recurring) else { return nil }
    return mapped
  }
}

/// An entry of ~/.claude/gh-pr-status-cache.json
struct ClaudePR: Hashable, Sendable {
  var url: String
  var number: Int
  var state: String
  var failed: Int
  var pending: Int
  var review: String?

  init?(url: String, _ d: [String: Any]) {
    guard let number = d["number"] as? Int, let state = d["state"] as? String else { return nil }
    self.url = url; self.number = number; self.state = state
    let checks = d["checks"] as? [String: Any]
    failed = checks?["failed"] as? Int ?? 0
    pending = checks?["pending"] as? Int ?? 0
    review = d["review"] as? String
  }

  init(url: String, number: Int, state: String, failed: Int = 0, pending: Int = 0, review: String? = nil) {
    self.url = url; self.number = number; self.state = state; self.failed = failed; self.pending = pending; self.review = review
  }

  /// merged / inactive / error / success / warning, as the agents view rates a PR.
  var health: String {
    switch state {
    case "MERGED": return "merged"
    case "OPEN":
      if failed > 0 || review == "CHANGES_REQUESTED" { return "error" }
      if pending == 0 && review != "REVIEW_REQUIRED" { return "success" }
      return "warning"
    default: return "inactive"
    }
  }

  var needsReview: Bool { state == "OPEN" && (health == "error" || (health == "warning" && review != "APPROVED")) }

  var token: AccentToken? {
    switch health { case "merged": .mauve; case "error": .red; case "success": .green; case "warning": .peach; default: nil }
  }

  var help: String {
    var parts = ["PR #\(number)", state.lowercased()]
    if failed > 0 { parts.append("\(failed) failing checks") }
    if pending > 0 { parts.append("\(pending) pending checks") }
    if let review { parts.append(review.lowercased().replacingOccurrences(of: "_", with: " ")) }
    return parts.joined(separator: " · ")
  }
}

/// The Rex pane a session runs in.
struct ClaudePane: Hashable, Sendable {
  var sessionID: String
  var sessionLabel: String
  var block: String
  var window: String?
}

struct ClaudeRow: Hashable, Sendable, Identifiable {
  var agent: ClaudeAgent
  var pane: ClaudePane?
  var group: ClaudeGroup
  var activity: ClaudeActivity
  var summary: String
  var message: String
  var prs: [ClaudePR]

  var id: String { agent.sessionId }

  var location: String {
    if let pane { return pane.sessionLabel }
    return agent.kind == "background" ? "background" : "outside Rex"
  }

  var help: String {
    if pane != nil { return "Go to this session in \(location)" }
    if agent.kind == "background" { return "Open in a new Rex tab" }
    return "Running outside Rex"
  }
}

/// Polls `claude agents` and the files under ~/.claude, matches each session to its Rex pane, and
/// opens a session in Rex: focus the pane it is in; a background agent gets a new tab running
/// `claude attach <id>`; an interactive session outside Rex can't be taken over, so a notice says so.
@MainActor @Observable
final class ClaudeProvider {
  nonisolated static let app = "claude-code"
  nonisolated static let defaultSessionLabel = "Claude"
  private(set) var rows: [ClaudeRow] = []
  private(set) var error: String? = nil
  private(set) var notice: String? = nil
  /// Bumped by `barrly://claude`; the widget on the first display toggles its list.
  private(set) var popupRequests = 0
  let cliPath: String?

  @ObservationIgnored private let log = Logger(subsystem: "dev.barrly", category: "claude")
  @ObservationIgnored private let scheduler: Scheduler
  @ObservationIgnored private let rex: RexProvider
  @ObservationIgnored private let settings: SettingsStore
  @ObservationIgnored private var token: Scheduler.Token? = nil
  @ObservationIgnored private var interval: TimeInterval = 2
  @ObservationIgnored private var refreshing = false
  @ObservationIgnored private var noticeTask: Task<Void, Never>? = nil
  @ObservationIgnored private var defaultSessionOpen: Task<Bool, Never>? = nil

  init(scheduler: Scheduler, rex: RexProvider, settings: SettingsStore) {
    self.scheduler = scheduler; self.rex = rex; self.settings = settings
    cliPath = Self.findCLI()
    interval = max(1, options?.interval ?? 2)
    token = scheduler.schedule(every: interval) { [weak self] in self?.refresh() }
  }

  /// `claude` on the usual paths. `BARRLY_CLAUDE_CLI` overrides.
  nonisolated static func findCLI() -> String? {
    var candidates: [String] = []
    if let env = ProcessInfo.processInfo.environment["BARRLY_CLAUDE_CLI"] { candidates.append(env) }
    candidates += [NSHomeDirectory() + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  nonisolated static var claudeDir: String { NSHomeDirectory() + "/.claude" }

  /// The placed widget's options (there is at most one Claude Code widget).
  var options: WidgetOptions? { settings.settings.layout.allWidgets.first { $0.kind == .claude }?.options }

  /// Sessions that need you: Needs input and Ready for review.
  var attentionCount: Int { rows.filter { $0.group == .blocked || $0.group == .review }.count }

  func requestPopup() { popupRequests += 1 }

  // MARK: Refresh

  func refresh() {
    if let t = token, let i = options?.interval, max(1, i) != interval { interval = max(1, i); scheduler.setInterval(t, interval) }
    guard let cli = cliPath, !refreshing else { return }
    refreshing = true
    let sessions = rex.state.sessions
    Task.detached(priority: .utility) { [weak self] in
      let r = await Subprocess.run(cli, ["agents", "--json", "--all"])
      let built = Self.build(r, rex: sessions)
      await MainActor.run { [weak self] in self?.apply(built) }
    }
  }

  private func apply(_ built: (rows: [ClaudeRow]?, error: String?)) {
    refreshing = false
    if let rows = built.rows, rows != self.rows { self.rows = rows }
    if built.error != error { error = built.error }
  }

  nonisolated private static func readJSON(_ path: String) -> Any? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  /// Rows from one `claude agents` run plus the files under ~/.claude and the Rex sessions.
  nonisolated static func build(_ r: Subprocess.Result, rex sessions: [RexSession]) -> (rows: [ClaudeRow]?, error: String?) {
    guard let list = r.json() as? [[String: Any]] else { return (nil, "claude agents --json failed: \(r.lastErrorLine)") }
    let prCache = (readJSON("\(claudeDir)/gh-pr-status-cache.json") as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
    let panes = sessions.flatMap { s in s.programs.map { (session: s, program: $0) } }
    let rows = list.compactMap { d -> ClaudeRow? in
      let file = (d["pid"] as? Int).flatMap { readJSON("\(claudeDir)/sessions/\($0).json") as? [String: Any] }
      guard let agent = ClaudeAgent(d, sessionFile: file) else { return nil }
      let match = findPane(for: agent, in: panes, arguments: { Subprocess.arguments(ofPid: Int32($0)) })
      let job = agent.id.flatMap { readJSON("\(claudeDir)/jobs/\($0)/state.json") as? [String: Any] }.map(ClaudeJob.init)
      let prs = (job?.prURLs ?? []).compactMap { url in prCache[url].flatMap { ClaudePR(url: url, $0) } }
      return makeRow(agent: agent, pane: match.map { ClaudePane(sessionID: $0.session.id, sessionLabel: $0.session.label, block: $0.program.block, window: $0.program.window) },
                     record: match?.program, job: job, prs: prs)
    }
    .sorted { a, b in a.group.rawValue != b.group.rawValue ? a.group.rawValue < b.group.rawValue : a.agent.startedAt > b.agent.startedAt }
    return (rows, nil)
  }

  /// A row's group (the list section) and activity (the card's status line). The group mirrors how
  /// the `claude agents` view groups sessions; `idle` is the only addition. Rex's record for the pane
  /// is the only source that knows a session is waiting on a permission, so a blocked record forces waiting.
  nonisolated static func makeRow(agent: ClaudeAgent, pane: ClaudePane?, record: RexProgram?, job: ClaudeJob?, prs: [ClaudePR]) -> ClaudeRow {
    let rexState = record?.state
    let message = record?.msg ?? ""
    let rexWaiting: String? = rexState == .blocked ? (record?.kind.map { "Needs \($0)" } ?? "Waiting for you") : nil
    let live = rexWaiting != nil ? "waiting" : agent.liveStatus
    let terminal = job?.terminal

    let group: ClaudeGroup = {
      if live == "busy" { return .working }
      guard let job else { return live == "waiting" ? .blocked : .idle }
      if terminal == "failure" || terminal == "stopped" { return .done }
      if live == "waiting" { return .blocked }
      if !job.recurring && prs.contains(where: \.needsReview) { return .review }
      if terminal == "success" { return .done }
      if job.tempo == "blocked" { return .blocked }
      return .working
    }()

    let activity: ClaudeActivity = {
      if let rexWaiting { return .waiting(rexWaiting) }
      if rexState == .working || live == "busy" { return .working }
      if live == "waiting" { return .waiting("Waiting for you") }
      if live == "shell" { return .shell }
      if rexState == .error || terminal == "failure" { return .failed }
      if terminal == "stopped" { return .stopped }
      if terminal == "success" { return .done }
      return .idle
    }()

    return ClaudeRow(agent: agent, pane: pane, group: group, activity: activity, summary: job?.detail ?? "", message: message, prs: prs)
  }

  /// The pane a session runs in: by pid for a live session (the reporting process or the pane's
  /// foreground process), else by the foreground command line (`claude attach <id>`, or the session
  /// id of a `--resume`). The pid match only applies to live sessions: a finished session's pid may
  /// have been reused.
  nonisolated static func findPane(for agent: ClaudeAgent, in panes: [(session: RexSession, program: RexProgram)],
                                   arguments: (Int) -> [String]) -> (session: RexSession, program: RexProgram)? {
    if agent.liveStatus != nil, let pid = agent.pid,
       let p = panes.first(where: { $0.program.pid == pid || $0.program.foregroundPid == pid }) { return p }
    return panes.first { p in
      guard let fg = p.program.foregroundPid else { return false }
      let words = arguments(fg)
      guard words.contains(where: { $0 == "claude" || $0.hasSuffix("/claude") }) else { return false }
      if let id = agent.id, let i = words.firstIndex(of: "attach"), i + 1 < words.count, words[i + 1] == id { return true }
      return words.contains { $0.contains(agent.sessionId) }
    }
  }

  // MARK: Opening

  /// Returns true when Rex was brought forward on the session; false when a notice explains why not.
  @discardableResult
  func open(_ row: ClaudeRow) async -> Bool {
    let agent = row.agent
    if let pane = row.pane {
      guard rex.cliPath != nil else { return show("The rex command was not found") }
      rex.select(block: pane.block, window: pane.window, in: pane.sessionID)
      return true
    }
    guard agent.kind == "background", let id = agent.id else {
      return show("\(agent.name) runs outside Rex and can't be opened from here")
    }
    guard rex.cliPath != nil else { return show("The rex command was not found") }
    let target = options?.claudeSession ?? ""
    if target.isEmpty {
      return await openInDefaultSession(agent, id: id)
    } else if let s = rex.state.sessions.first(where: { $0.label == target }) {
      return await openTab(agent, id: id, in: s.id)
    } else {
      return show("No Rex session named “\(target)”. Choose another in Barrly's settings.")
    }
  }

  private func attachCommand(_ id: String) -> [String] { [cliPath ?? "claude", "attach", id] }

  private func openTab(_ agent: ClaudeAgent, id: String, in session: String) async -> Bool {
    let r = await rex.call(["window", "new", "-s", session, agent.name, "-c", agent.cwd, "--json", "--"] + attachCommand(id))
    guard r.ok else { return show("Couldn't open \(agent.name): \(r.lastErrorLine)") }
    let window = (r.json() as? [String: Any])?["window_id"] as? String
    rex.select(block: nil, window: window, in: session)
    refresh()
    return true
  }

  /// Rex allows duplicate session labels, so these run one at a time against a fresh session list:
  /// two quick clicks must not create two Claude sessions.
  private func openInDefaultSession(_ agent: ClaudeAgent, id: String) async -> Bool {
    let previous = defaultSessionOpen
    let work = Task { @MainActor () -> Bool in
      _ = await previous?.value
      let ls = await rex.call(["ls", "--json"])
      guard let list = ls.json() as? [String: Any] else { return show("Couldn't reach Rex to open \(agent.name)") }
      let sessions = (list["sessions"] as? [[String: Any]] ?? []).compactMap { s -> (id: String, label: String)? in
        guard let id = s["session_id"] as? String else { return nil }
        return (id, (s["label"] as? String) ?? id)
      }
      if let existing = sessions.first(where: { $0.label == Self.defaultSessionLabel }) {
        return await openTab(agent, id: id, in: existing.id)
      }
      // The session's first window runs the attach, so no empty shell tab is left behind.
      let r = await rex.call(["new", Self.defaultSessionLabel, "--window", agent.name, "-c", agent.cwd, "--json", "--"] + attachCommand(id))
      guard r.ok, let created = r.json() as? [String: Any], let session = created["session_id"] as? String else {
        return show("Couldn't create the \(Self.defaultSessionLabel) session: \(r.lastErrorLine)")
      }
      let window = (created["initial_windows"] as? [[String: Any]])?.first?["window_id"] as? String
      rex.select(block: nil, window: window, in: session)
      refresh()
      return true
    }
    defaultSessionOpen = work
    return await work.value
  }

  /// Shows a notice for a few seconds; returns false so callers can `return show(…)`.
  @discardableResult
  private func show(_ message: String) -> Bool {
    notice = message
    noticeTask?.cancel()
    noticeTask = Task {
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled { notice = nil }
    }
    return false
  }

  // MARK: Formatting

  nonisolated static func age(from start: Date, to now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(start)))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
  }

  nonisolated static func shortPath(_ p: String, home: String = NSHomeDirectory()) -> String {
    p == home || p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
  }
}
