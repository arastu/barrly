import AppKit
import SwiftUI

/// Every Claude Code session, Tea style: the Claude app icon, a green dot while a session works, and
/// how many sessions need you (Needs input and Ready for review); click opens the list, grouped by
/// status, and a session in it opens in Rex.
struct ClaudeWidget: View {
  /// The Claude desktop app, whose icon the chip shows; Tea's cup stands in when it isn't installed.
  static let claudeAppBundleID = "com.anthropic.claudefordesktop"
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var box = AnchorBox()

  var body: some View {
    let c = runtime.claude
    let count = c.attentionCount
    let urgent = c.rows.contains { $0.group == .blocked }
    let working = c.rows.contains { $0.activity == .working }
    WidgetCell(spec: spec, onClick: toggle) {
      HStack(spacing: theme.metrics.iconLabelSpacing) {
        Group {
          if let icon = AppIconCache.shared.icon(bundleId: Self.claudeAppBundleID) {
            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
          } else {
            Image(systemName: "cup.and.saucer.fill").font(theme.fonts.icon)
              .foregroundStyle(theme.iconTint(for: spec) ?? Color.primary)
          }
        }
        // A green dot while any session works.
        .overlay(alignment: .topTrailing) {
          if working {
            let green = theme.stateColor(.green)
            Circle().fill(green).frame(width: 6, height: 6)
              .overlay(Circle().strokeBorder(theme.isDark ? Color.black.opacity(0.6) : Color.white.opacity(0.9), lineWidth: 1))
              .shadow(color: green.opacity(0.8), radius: 2)
              .offset(x: 3, y: -3)
          }
        }
        .animation(theme.stateAnimation, value: working)
        if count > 0 {
          Text("\(count)").font(theme.fonts.label).monospacedDigit()
            .foregroundStyle(theme.stateColor(urgent ? .peach : .mauve))
        }
      }
      .accessibilityLabel(Text((count > 0 ? "Claude Code, \(count) sessions need you" : "Claude Code") + (working ? ", working" : "")))
    }
    .background(AnchorView(box: box))
    .onChange(of: c.popupRequests) { _, _ in if box.window?.screen == NSScreen.screens.first { toggle() } }
    .onDisappear { if PopupPanel.sessions.owner == spec.id { PopupPanel.sessions.hide() } }
  }

  private func toggle() {
    guard let frame = box.screenFrame else { return }
    PopupPanel.sessions.toggle(owner: spec.id, ClaudeSessionsView(specID: spec.id).environment(runtime), anchor: frame, parent: box.window, theme: theme)
  }
}

/// The list: sessions grouped by status, each one a card.
struct ClaudeSessionsView: View {
  let specID: UUID
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme

  var body: some View {
    let c = runtime.claude
    let collapsed = Set(runtime.settings.spec(id: specID)?.options.collapsedSections ?? [])
    ListPanel(title: "Claude Code", error: c.error, notice: c.notice, isEmpty: c.rows.isEmpty, emptyText: "No Claude sessions") {
      // Ages tick every second while the list is open.
      TimelineView(.periodic(from: .now, by: 1)) { context in
        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
          ForEach(ClaudeGroup.allCases) { group in
            let rows = c.rows.filter { $0.group == group }
            if !rows.isEmpty {
              let hidden = collapsed.contains(group.rawValue)
              Section {
                if !hidden {
                  ForEach(rows) { row in
                    // Like Tea's popover, the list closes once Rex comes forward; it stays for a notice.
                    Button { Task { if await c.open(row) { PopupPanel.sessions.hide() } } } label: { ClaudeCard(row: row, now: context.date) }
                      .buttonStyle(.plain)
                      .padding(.horizontal, 8)
                  }
                }
              } header: {
                ListSectionHeader(title: group.title, count: rows.count, color: group.token.map { theme.stateColor($0) }, collapsed: hidden) {
                  withAnimation(theme.hoverAnimation) { toggleCollapsed(group.rawValue) }
                }
              }
            }
          }
        }
      }
    }
  }

  /// Collapsed sections are kept across launches, in the widget's options.
  private func toggleCollapsed(_ key: Int) {
    runtime.settings.update(specID) { spec in
      if let i = spec.options.collapsedSections.firstIndex(of: key) { spec.options.collapsedSections.remove(at: i) }
      else { spec.options.collapsedSections.append(key); spec.options.collapsedSections.sort() }
    }
  }
}

/// One session: activity icon, name and age, the status line, Claude's message, the job summary,
/// linked PRs and the working directory.
struct ClaudeCard: View {
  let row: ClaudeRow
  let now: Date
  @Environment(\.theme) private var theme

  var body: some View {
    let activityColor = row.activity.token.map { theme.stateColor($0) } ?? theme.palette.text2
    ListCard(symbol: row.activity.symbol, color: activityColor, title: row.agent.name,
             trailing: ClaudeProvider.age(from: row.agent.startedAt, to: now), help: row.help) {
      HStack(spacing: 4) {
        Text(row.activity.label).foregroundStyle(activityColor)
        Text("·").foregroundStyle(theme.palette.text3)
        Text(row.location).foregroundStyle(theme.palette.text2)
      }
      .font(.caption)
      if !row.message.isEmpty {
        Text(row.message).font(.caption).italic().foregroundStyle(theme.palette.text).lineLimit(2)
      }
      if !row.summary.isEmpty {
        Text(row.summary).font(.caption).foregroundStyle(theme.palette.text.opacity(0.8)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
      }
      if !row.prs.isEmpty {
        HStack(spacing: 6) {
          ForEach(row.prs, id: \.url) { pr in
            let color = pr.token.map { theme.stateColor($0) } ?? theme.palette.text2
            Text("#\(String(pr.number))").font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(color)
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(Capsule().fill(color.opacity(0.15)))
              .help(pr.help)
          }
        }
      }
      Text(ClaudeProvider.shortPath(row.agent.cwd)).font(.caption2).foregroundStyle(theme.palette.text3).lineLimit(1).truncationMode(.middle)
    }
  }
}
