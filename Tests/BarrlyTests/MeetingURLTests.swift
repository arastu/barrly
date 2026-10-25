import Foundation
import Testing
@testable import Barrly

@Suite struct MeetingURLTests {
  @Test func findsZoomInNotes() {
    let u = MeetingURLExtractor.extract(from: [nil, "Join: https://us02web.zoom.us/j/123456789?pwd=abc. Thanks", "Room 4"])
    #expect(u?.host == "us02web.zoom.us")
    #expect(u?.absoluteString.hasSuffix(".") == false)
  }
  @Test func prefersEventURL() {
    let u = MeetingURLExtractor.extract(from: ["https://meet.google.com/abc-defg-hij", "https://zoom.us/j/1"])
    #expect(u?.host == "meet.google.com")
  }
  @Test func ignoresNonMeetingLinks() {
    #expect(MeetingURLExtractor.extract(from: ["see https://example.com/doc"]) == nil)
    #expect(MeetingURLExtractor.extract(from: [nil, nil]) == nil)
  }
  @Test func teams() {
    let u = MeetingURLExtractor.extract(from: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x>"])
    #expect(u?.host == "teams.microsoft.com")
  }
}
