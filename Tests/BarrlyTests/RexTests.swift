import Foundation
import Testing
@testable import Barrly

@Suite struct RexTests {
  @Test func parsesWatcherLine() {
    let line = Data(#"{"sessions":[{"id":"session:1","label":"work","blocks":3,"state":"idle"},{"id":"session:2","label":"agent","blocks":1,"state":"blocked","app":"claude","kind":"permission","msg":"Run tests?"}]}"#.utf8)
    let s = RexProvider.parse(line)
    #expect(s?.count == 2)
    #expect(s?[0].state == .idle && s?[0].blocks == 3 && s?[0].app == nil)
    #expect(s?[1].state == .blocked && s?[1].app == "claude" && s?[1].kind == "permission" && s?[1].msg == "Run tests?")
    #expect(RexProvider.parse(Data("listening: 9 handlers, every session".utf8)) == nil)
    #expect(RexProvider.parse(Data(#"{"error":"boom"}"#.utf8)) == nil)
    let unknown = RexProvider.parse(Data(#"{"sessions":[{"id":"session:3","label":"x","blocks":1,"state":"something-new"}]}"#.utf8))
    #expect(unknown?.first?.state == .idle)
    #expect(RexSession.State.blocked > .error && RexSession.State.error > .working && RexSession.State.working > .done)
    // Agent counts are optional, so an older watcher parses with zeros.
    #expect(s?[0].agents == 0 && s?[1].blocked == 0)
    let counted = RexProvider.parse(Data(#"{"sessions":[{"id":"session:4","label":"swarm","blocks":4,"state":"working","agents":3,"working":2,"blocked":1}],"summary":{"agents":3}}"#.utf8))
    #expect(counted?.first?.agents == 3 && counted?.first?.working == 2 && counted?.first?.blocked == 1)
  }

  @Test @MainActor func agentCounts() {
    let idle = RexSession(id: "session:1", label: "work", blocks: 2, state: .idle)
    let swarm = RexSession(id: "session:2", label: "swarm", blocks: 4, state: .working, app: "claude-code", agents: 3, working: 3)
    let waiting = RexSession(id: "session:3", label: "api", blocks: 2, state: .blocked, app: "claude-code", kind: "question", agents: 2, working: 0, blocked: 2)
    let state = RexState(connected: true, sessions: [idle, swarm, waiting])
    #expect(state.agents == 5 && state.working == 3 && state.blocked == 2)
    // Working agents don't change the chip (the Claude Code widget shows that); it stays the session count.
    let busy = RexWidget.describe(RexState(connected: true, sessions: [idle, swarm]), clip: 24, showCount: true)
    #expect(busy.label == "2" && busy.tint == nil)
    // A waiting session names itself and counts the other agents waiting on the user.
    let attention = RexWidget.describe(state, clip: 24, showCount: true)
    #expect(attention.label == "api · waiting +1" && attention.tint == .peach)
    #expect(RexWidget.word(for: swarm) == "Working" && RexWidget.panes(for: swarm) == "4 panes · 3 agents")
    // Only sessions with agents report them; an idle session with none is just panes.
    #expect(RexWidget.panes(for: RexSession(id: "session:5", label: "x", blocks: 1, state: .idle, agents: 1)) == "1 pane · 1 agent")
  }

  @Test func programRecords() {
    let line = #"{"sessions":[{"id":"session:1","label":"api","blocks":3,"state":"blocked","kind":"permission","agents":2,"working":1,"blocked":1,"programs":[{"block":"block:a","app":"claude-code","state":"working","msg":"Running tests"},{"block":"block:b","app":"claude-code","state":"blocked","kind":"permission"},{"block":"block:c","app":"codex","state":"done"}]}]}"#
    let s = RexProvider.parse(Data(line.utf8))?.first
    #expect(s?.programs.count == 3)
    // Strongest first, so a pane waiting on the user leads.
    #expect(s?.programs.first?.block == "block:b" && s?.programs.first?.state == .blocked && s?.programs.first?.kind == "permission")
    #expect(s?.programs[1].msg == "Running tests")
    // Older watchers send no programs; an empty Lua table may arrive as an object.
    #expect(RexProvider.parse(Data(#"{"sessions":[{"id":"session:2","label":"x","blocks":1,"state":"idle","programs":{}}]}"#.utf8))?.first?.programs.isEmpty == true)
    let state = RexState(connected: true, sessions: [s!])
    let claude = state.programs(app: "claude-code")
    #expect(claude.map(\.program.block) == ["block:b", "block:a"] && claude.first?.session.label == "api")
    #expect(state.programs(app: "codex").count == 1)
  }

  @Test func programPanes() {
    // Newer watchers add the window, the reporting process and the pane's foreground process.
    let line = #"{"sessions":[{"id":"session:1","label":"api","blocks":1,"state":"working","agents":1,"working":1,"programs":[{"block":"block:a","window":"window:1","app":"claude-code","state":"working","pid":500,"fg":501}]}]}"#
    let p = RexProvider.parse(Data(line.utf8))?.first?.programs.first
    #expect(p?.window == "window:1" && p?.pid == 500 && p?.foregroundPid == 501)
    #expect(RexProvider.parse(Data(#"{"sessions":[{"id":"session:2","label":"x","blocks":1,"state":"idle","programs":[{"block":"block:b","app":"codex","state":"idle"}]}]}"#.utf8))?.first?.programs.first?.pid == nil)
  }

  @Test @MainActor func chipLabel() {
    let idle = RexSession(id: "session:1", label: "work", blocks: 2, state: .idle)
    let blocked = RexSession(id: "session:2", label: "a-very-long-session-label", blocks: 1, state: .blocked, app: "claude", kind: "permission")
    let failed = RexSession(id: "session:3", label: "build", blocks: 1, state: .error)
    let working = RexSession(id: "session:4", label: "deploy", blocks: 1, state: .working, app: "cargo")

    let plain = RexWidget.describe(RexState(connected: true, sessions: [idle]), clip: 24, showCount: true)
    #expect(plain.label == "1" && plain.tint == nil)
    #expect(RexWidget.describe(RexState(connected: true, sessions: [idle]), clip: 24, showCount: false).label == nil)
    let busy = RexWidget.describe(RexState(connected: true, sessions: [idle, working]), clip: 24, showCount: true)
    #expect(busy.label == "2" && busy.tint == nil)
    // Blocked outranks failed, the label is clipped before the suffix, and the rest are counted.
    let attention = RexWidget.describe(RexState(connected: true, sessions: [idle, failed, blocked]), clip: 24, showCount: true)
    #expect(attention.label == "a-very-long-session-lab… · approve +1" && attention.tint == .peach)
    let justFailed = RexWidget.describe(RexState(connected: true, sessions: [failed, working]), clip: 24, showCount: true)
    #expect(justFailed.label == "build · failed" && justFailed.tint == .red)

    #expect(RexWidget.panes(for: idle) == "2 panes" && RexWidget.word(for: idle) == "Idle")
    #expect(RexWidget.word(for: blocked) == "Needs permission" && RexWidget.word(for: RexSession(id: "s", label: "y", blocks: 1, state: .blocked)) == "Waiting for you")
    #expect(RexWidget.word(for: working) == "Working" && RexWidget.word(for: failed) == "Failed")
    #expect(RexWidget.word(for: .idle) == nil && RexWidget.word(for: .blocked, kind: "permission") == "Needs permission")
  }

  @Test func panes() {
    let line = #"{"sessions":[{"id":"session:1","label":"work","blocks":2,"state":"working","panes":[{"block":"block:a","window":"window:1","label":"shell","name":"claude","cwd":"/Users/me/Code/app","pid":10,"state":"working","app":"claude-code","msg":"Editing","updated":"2026-11-07T11:40:30.991392+03:30","title":"Fix login","title_pid":10},{"block":"block:b","name":"zsh","cwd":"/Users/me","pid":11,"title":"me@mac:~","title_pid":11}]}]}"#
    let s = RexProvider.parse(Data(line.utf8))?.first
    #expect(s?.panes.count == 2)
    let claude = s!.panes[0], shell = s!.panes[1]
    #expect(claude.state == .working && claude.app == "claude-code" && claude.title == "Fix login" && claude.window == "window:1")
    #expect(claude.updatedAt == RexProvider.parseDate("2026-11-07T08:10:30.991Z"))
    #expect(shell.state == .idle && shell.app == nil && shell.pid == 11)
    // A shell shows where it is; a program shows the title it set, or where it is without one.
    #expect(RexWidget.secondary(for: shell, home: "/Users/me") == "~")
    #expect(RexWidget.secondary(for: claude, home: "/Users/me") == "Fix login")
    #expect(RexWidget.secondary(for: RexPane(block: "x", name: "nvim", cwd: "/Users/me/Code/app"), home: "/Users/me") == "~/Code/app")
    // A title that just repeats the name (Claude Code at rest) adds nothing.
    #expect(RexWidget.secondary(for: RexPane(block: "x", name: "claude", cwd: "/Users/me/app", pid: 5, title: "Claude Code", titlePid: 5), home: "/Users/me") == "~/app")
    // A title left by another process (a shell's prompt title under a program) doesn't count.
    #expect(RexWidget.secondary(for: RexPane(block: "x", name: "cargo", cwd: "/tmp", pid: 5, title: "me@mac", titlePid: 4), home: "/Users/me") == "/tmp")
    #expect(RexWidget.displayName("claude") == "Claude Code" && RexWidget.displayName("nvim") == "Neovim" && RexWidget.displayName("htop") == "htop" && RexWidget.displayName(nil) == "pane")
    #expect(RexWidget.isShell("zsh") && RexWidget.isShell("fish") && !RexWidget.isShell("claude") && !RexWidget.isShell(nil))
    #expect(RexWidget.stableKey("session:1") == RexWidget.stableKey("session:1") && RexWidget.stableKey("session:1") != RexWidget.stableKey("session:2"))
    // Older watchers send no panes; timestamps without fractions parse too.
    #expect(RexProvider.parse(Data(#"{"sessions":[{"id":"session:2","label":"x","blocks":1,"state":"idle"}]}"#.utf8))?.first?.panes.isEmpty == true)
    #expect(RexProvider.parseDate("2026-11-07T08:10:30Z") != nil && RexProvider.parseDate("nope") == nil)
  }
}
