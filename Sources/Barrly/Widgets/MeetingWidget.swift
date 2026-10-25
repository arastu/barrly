import SwiftUI

/// Current / next meeting, MeetingBar style, in its own tinted capsule. Hover shows the full title.
struct MeetingWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var hovering = false

  var body: some View {
    let cal = runtime.calendar
    let now = runtime.clock.now
    if let m = cal.meeting {
      let (label, color) = Self.describe(m, now: now, clip: spec.options.clipChars, theme: theme)
      WidgetCell(spec: spec, onClick: { join(m) }) {
        IconLabel(symbol: "video.fill", label: label, iconColor: theme.palette.accent(.lavender), labelFont: theme.fonts.persian)
          .foregroundStyle(color)
      }
      .onHover { hovering = $0 }
      .popover(isPresented: $hovering, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Text(m.title).font(.headline)
          Text("\(m.start.formatted(date: .omitted, time: .shortened)) – \(m.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
          if let url = m.url { Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.tertiary) }
        }.padding(12)
      }
      .onChange(of: spec.options.soonMinutes, initial: true) { _, v in cal.soonMinutes = v }
    }
  }

  static func describe(_ m: Meeting, now: Date, clip: Int, theme: ResolvedTheme) -> (String, Color) {
    let title = m.title.count > clip ? String(m.title.prefix(max(1, clip - 1))) + "…" : m.title
    func fmt(_ secs: TimeInterval) -> String { let mins = max(0, Int(secs / 60)); return mins >= 60 ? "\(mins / 60)h\(String(format: "%02d", mins % 60))m" : "\(mins)m" }
    switch m.phase {
    case .inProgress: return ("\(title) · \(fmt(m.end.timeIntervalSince(now))) left", theme.palette.accent(.peach))
    case .soon: return ("\(title) · in \(fmt(m.start.timeIntervalSince(now)))", theme.palette.accent(.yellow))
    case .later: return ("\(title) · \(m.start.formatted(date: .omitted, time: .shortened))", theme.palette.accent(.lavender))
    }
  }

  private func join(_ m: Meeting) {
    if let url = m.url { NSWorkspace.shared.open(url) } else { runtime.open(app: "Calendar") }
  }
}
