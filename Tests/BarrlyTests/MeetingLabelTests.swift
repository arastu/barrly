import Foundation
import Testing
@testable import Barrly

@Suite struct MeetingLabelTests {
  @Test @MainActor func phases() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let t = ResolvedTheme.preview
    let inProgress = Meeting(title: "Weekly sync with the platform team", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(23 * 60), url: nil, phase: .inProgress)
    let a = MeetingWidget.describe(inProgress, now: now, clip: 16, theme: t); #expect(a.title == "Weekly sync wit…" && a.detail == "23m left")
    let soon = Meeting(title: "1:1", start: now.addingTimeInterval(5 * 60), end: now.addingTimeInterval(35 * 60), url: nil, phase: .soon)
    #expect(MeetingWidget.describe(soon, now: now, clip: 16, theme: t).detail == "in 5m")
    let long = Meeting(title: "Offsite", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(125 * 60), url: nil, phase: .inProgress)
    #expect(MeetingWidget.describe(long, now: now, clip: 16, theme: t).detail == "2h05m left")
  }
}
