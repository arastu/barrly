import Foundation

/// Finds the join link of a meeting in its URL, notes or location.
enum MeetingURLExtractor {
  static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                      "skype.com", "whereby.com", "around.co", "gather.town", "meet.jit.si", "discord.gg"]
  private static let regex = try! NSRegularExpression(pattern: #"https?://[^\s<>"'()\]]+"#)

  static func extract(from texts: [String?]) -> URL? {
    for t in texts.compactMap({ $0 }) {
      for m in regex.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
        guard let r = Range(m.range, in: t) else { continue }
        var s = String(t[r])
        while let last = s.last, ".,;:".contains(last) { s.removeLast() }
        guard let url = URL(string: s), let host = url.host?.lowercased() else { continue }
        if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
      }
    }
    return nil
  }
}
