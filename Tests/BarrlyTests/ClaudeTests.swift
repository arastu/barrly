import Foundation
import Testing
@testable import Barrly

@Suite struct ClaudeTests {
  static func agent(_ extra: [String: Any] = [:], file: [String: Any]? = nil) -> ClaudeAgent {
    var d: [String: Any] = ["sessionId": "s-1", "name": "fix login", "cwd": "/tmp/acme", "kind": "interactive", "startedAt": 1_794_000_000_000.0]
    for (k, v) in extra { d[k] = v }
    return ClaudeAgent(d, sessionFile: file)!
  }
  static func job(_ extra: [String: Any] = [:]) -> ClaudeJob {
    var d: [String: Any] = ["state": "done", "tempo": "idle", "detail": "Opened a PR."]
    for (k, v) in extra { d[k] = v }
    return ClaudeJob(d)
  }

  @Test func parsesAgents() {
    let a = Self.agent(["pid": 10, "status": "busy"], file: ["sessionId": "s-1", "status": "shell", "entrypoint": "cli"])
    // The session file is more precise than `claude agents --json`, which reports a shell as busy.
    #expect(a.liveStatus == "shell" && a.pid == 10 && a.kind == "interactive")
    // A file for another session is ignored; without a reported status there is no live status.
    #expect(Self.agent(["status": "busy"], file: ["sessionId": "other", "status": "idle"]).liveStatus == "busy")
    #expect(Self.agent(["id": "84ea90b3", "kind": "background"]).liveStatus == nil)
    #expect(ClaudeAgent(["sessionId": "s-2", "pid": 3, "status": "idle"], sessionFile: ["sessionId": "s-2", "entrypoint": "sdk-cli"]) == nil)
    #expect(ClaudeAgent(["name": "no id"], sessionFile: nil) == nil)
    #expect(ClaudeAgent(["sessionId": "s-3", "id": "abc"], sessionFile: nil)?.name == "abc")
  }

  @Test func jobsAndPRs() {
    #expect(Self.job().terminal == "success")
    #expect(Self.job(["state": "failed"]).terminal == "failure")
    #expect(Self.job(["state": "stopped"]).terminal == "stopped")
    #expect(Self.job(["state": "running"]).terminal == nil)
    // Still active, or a recurring job that finished a run, isn't done.
    #expect(Self.job(["tempo": "active"]).terminal == nil)
    #expect(Self.job(["intent": " /loop 5m check CI"]).recurring && Self.job(["intent": "/loop 5m check CI"]).terminal == nil)
    #expect(Self.job(["selfWake": true]).recurring && Self.job(["inFlight": ["kinds": ["session_cron"]]]).recurring)
    #expect(Self.job(["routine": ["id": 1], "state": "failed"]).terminal == "failure")
    #expect(Self.job(["children": [["kind": "pr", "href": "https://g/1"], ["kind": "issue", "href": "https://g/2"]]]).prURLs == ["https://g/1"])

    let open = ClaudePR(url: "u", number: 142, state: "OPEN", failed: 1)
    #expect(open.health == "error" && open.needsReview && open.token == .red)
    #expect(ClaudePR(url: "u", number: 1, state: "OPEN").health == "success" && !ClaudePR(url: "u", number: 1, state: "OPEN").needsReview)
    let pending = ClaudePR(url: "u", number: 1, state: "OPEN", pending: 2)
    #expect(pending.health == "warning" && pending.needsReview)
    #expect(!ClaudePR(url: "u", number: 1, state: "OPEN", pending: 2, review: "APPROVED").needsReview)
    #expect(ClaudePR(url: "u", number: 1, state: "OPEN", review: "CHANGES_REQUESTED").health == "error")
    #expect(ClaudePR(url: "u", number: 1, state: "OPEN", review: "REVIEW_REQUIRED").health == "warning")
    #expect(ClaudePR(url: "u", number: 1, state: "MERGED").health == "merged" && ClaudePR(url: "u", number: 1, state: "CLOSED").health == "inactive")
    #expect(ClaudePR(url: "u", number: 7, state: "OPEN", failed: 1, review: "CHANGES_REQUESTED").help == "PR #7 · open · 1 failing checks · changes requested")
    #expect(ClaudePR(url: "u", ["number": 3, "state": "OPEN", "checks": ["failed": 0, "pending": 1]])?.pending == 1)
    #expect(ClaudePR(url: "u", ["state": "OPEN"]) == nil)
  }

  @Test func grouping() {
    func row(_ agent: ClaudeAgent, record: RexProgram? = nil, job: ClaudeJob? = nil, prs: [ClaudePR] = []) -> ClaudeRow {
      ClaudeProvider.makeRow(agent: agent, pane: nil, record: record, job: job, prs: prs)
    }
    // Interactive sessions: busy works, waiting needs input, otherwise idle.
    #expect(row(Self.agent(["status": "busy"])).group == .working && row(Self.agent(["status": "busy"])).activity == .working)
    #expect(row(Self.agent(["status": "waiting"])).group == .blocked && row(Self.agent(["status": "waiting"])).activity == .waiting("Waiting for you"))
    #expect(row(Self.agent(["status": "idle"])).group == .idle && row(Self.agent(["status": "idle"])).activity == .idle)
    #expect(row(Self.agent(["status": "shell"])).group == .idle && row(Self.agent(["status": "shell"])).activity == .shell)
    // Rex knows about permission prompts even when the session's own status lags.
    let blocked = RexProgram(block: "b", app: "claude-code", state: .blocked, kind: "permission", msg: "Run the migrations?")
    let r = row(Self.agent(["status": "busy"]), record: blocked)
    #expect(r.group == .blocked && r.activity == .waiting("Needs permission") && r.message == "Run the migrations?")
    #expect(row(Self.agent(["status": "idle"]), record: RexProgram(block: "b", app: "claude-code", state: .blocked)).activity == .waiting("Waiting for you"))
    #expect(row(Self.agent(["status": "idle"]), record: RexProgram(block: "b", app: "claude-code", state: .working)).activity == .working)
    #expect(row(Self.agent(["status": "idle"]), record: RexProgram(block: "b", app: "claude-code", state: .error)).activity == .failed)
    // Background agents follow their job.
    let bg = Self.agent(["id": "a1", "kind": "background"])
    let done = row(bg, job: Self.job())
    #expect(done.group == .done && done.activity == .done && done.summary == "Opened a PR.")
    #expect(row(bg, job: Self.job(["state": "failed"])).group == .done && row(bg, job: Self.job(["state": "failed"])).activity == .failed)
    #expect(row(bg, job: Self.job(["state": "stopped"])).activity == .stopped)
    #expect(row(bg, job: Self.job(["state": "running", "tempo": "active"])).group == .working)
    #expect(row(bg, job: Self.job(["state": "running", "tempo": "blocked"])).group == .blocked)
    #expect(row(bg, job: Self.job(["state": "running", "tempo": "active"])).activity == .idle)
    // A finished job with a PR that needs attention is ready for review; not for recurring jobs.
    let failing = ClaudePR(url: "https://g/142", number: 142, state: "OPEN", failed: 1)
    #expect(row(bg, job: Self.job(), prs: [failing]).group == .review)
    #expect(row(bg, job: Self.job(["selfWake": true]), prs: [failing]).group == .working)
    #expect(row(bg, job: Self.job(), prs: [ClaudePR(url: "u", number: 1, state: "MERGED")]).group == .done)
    // Waiting beats review; a failed job beats waiting.
    #expect(row(bg, record: blocked, job: Self.job(), prs: [failing]).group == .blocked)
    #expect(row(bg, record: blocked, job: Self.job(["state": "failed"])).group == .done)
  }

  @Test func findsPane() {
    let s = RexSession(id: "session:1", label: "Work", blocks: 2, state: .working)
    let byOwner = RexProgram(block: "block:a", app: "claude-code", state: .working, window: "window:1", pid: 10, foregroundPid: 11)
    let attach = RexProgram(block: "block:b", app: "claude-code", state: .idle, pid: 20, foregroundPid: 20)
    let resumed = RexProgram(block: "block:c", app: "claude-code", state: .idle, foregroundPid: 30)
    let panes = [(session: s, program: byOwner), (session: s, program: attach), (session: s, program: resumed)]
    let argv: (Int) -> [String] = { pid in
      switch pid {
      case 20: ["/opt/homebrew/bin/claude", "attach", "a1"]
      case 30: ["claude", "--resume", "s-1"]
      default: []
      }
    }
    // A live session matches by pid: the reporting process or the pane's foreground process.
    #expect(ClaudeProvider.findPane(for: Self.agent(["pid": 10, "status": "busy"]), in: panes, arguments: argv)?.program.block == "block:a")
    #expect(ClaudeProvider.findPane(for: Self.agent(["pid": 11, "status": "busy"]), in: panes, arguments: argv)?.program.block == "block:a")
    // A finished session's pid may have been reused, so only the command line counts.
    #expect(ClaudeProvider.findPane(for: Self.agent(["pid": 10, "id": "a1", "kind": "background"]), in: panes, arguments: argv)?.program.block == "block:b")
    #expect(ClaudeProvider.findPane(for: Self.agent(["pid": 10, "id": "zz", "kind": "background"]), in: panes, arguments: argv)?.program.block == "block:c")
    #expect(ClaudeProvider.findPane(for: Self.agent(["sessionId": "s-9", "id": "zz", "kind": "background"]), in: panes, arguments: argv) == nil)
    #expect(ClaudeProvider.findPane(for: Self.agent(["pid": 99, "status": "idle"]), in: [], arguments: argv) == nil)

    let row = ClaudeProvider.makeRow(agent: Self.agent(["status": "busy"]), pane: ClaudePane(sessionID: s.id, sessionLabel: s.label, block: "block:a", window: nil), record: byOwner, job: nil, prs: [])
    #expect(row.location == "Work" && row.help == "Go to this session in Work")
    #expect(ClaudeProvider.makeRow(agent: Self.agent(["id": "a1", "kind": "background"]), pane: nil, record: nil, job: nil, prs: []).location == "background")
    #expect(ClaudeProvider.makeRow(agent: Self.agent(["status": "idle"]), pane: nil, record: nil, job: nil, prs: []).help == "Running outside Rex")
  }

  @Test func formatting() {
    let t = Date(timeIntervalSince1970: 1_000_000)
    #expect(ClaudeProvider.age(from: t, to: t.addingTimeInterval(42)) == "42s")
    #expect(ClaudeProvider.age(from: t, to: t.addingTimeInterval(42 * 60)) == "42m")
    #expect(ClaudeProvider.age(from: t, to: t.addingTimeInterval(7 * 3600)) == "7h")
    #expect(ClaudeProvider.age(from: t, to: t.addingTimeInterval(3 * 86400)) == "3d")
    #expect(ClaudeProvider.age(from: t.addingTimeInterval(5), to: t) == "0s")
    #expect(ClaudeProvider.shortPath("/Users/me/Code/acme", home: "/Users/me") == "~/Code/acme")
    #expect(ClaudeProvider.shortPath("/Users/me", home: "/Users/me") == "~")
    #expect(ClaudeProvider.shortPath("/Users/meow/x", home: "/Users/me") == "/Users/meow/x")
    #expect(ClaudeGroup.allCases.map(\.title) == ["Ready for review", "Needs input", "Working", "Idle", "Completed"])
    // Our own command line is readable; a dead pid is not.
    #expect(Subprocess.arguments(ofPid: ProcessInfo.processInfo.processIdentifier).isEmpty == false)
    #expect(Subprocess.arguments(ofPid: 2_000_000_000).isEmpty)
  }
}
