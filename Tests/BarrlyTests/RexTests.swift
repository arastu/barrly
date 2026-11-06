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
    #expect(busy.label == "2" && busy.tint == .blue)
    // Blocked outranks failed, the label is clipped before the suffix, and the rest are counted.
    let attention = RexWidget.describe(RexState(connected: true, sessions: [idle, failed, blocked]), clip: 24, showCount: true)
    #expect(attention.label == "a-very-long-session-lab… · approve +1" && attention.tint == .peach)
    let justFailed = RexWidget.describe(RexState(connected: true, sessions: [failed, working]), clip: 24, showCount: true)
    #expect(justFailed.label == "build · failed" && justFailed.tint == .red)

    #expect(RexWidget.detail(for: idle) == "2 panes")
    #expect(RexWidget.detail(for: blocked) == "claude · needs approval")
    #expect(RexWidget.detail(for: working) == "cargo · working")
  }
}
