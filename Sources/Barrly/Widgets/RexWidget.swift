import AppKit
import SwiftUI

/// Rex sessions, shown while Rex runs: the session count, or the session a program is waiting on
/// (OSC 7501 blocked / error). Hover lists every session; click opens Rex, on that session.
struct RexWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var hovering = false

  var body: some View {
    let r = runtime.rex.state
    if r.connected {
      let d = Self.describe(r, clip: spec.options.clipChars, showCount: spec.options.showName)
      let tint = d.tint.map { theme.stateColor($0) }
      WidgetCell(spec: spec, onClick: { open(r) }) {
        HStack(spacing: theme.metrics.iconLabelSpacing) {
          Image(systemName: "terminal").font(theme.fonts.icon)
            .foregroundStyle(tint ?? theme.iconTint(for: spec) ?? Color.primary)
          if let label = d.label {
            Text(label).font(theme.fonts.label).foregroundStyle(tint ?? theme.palette.text).lineLimit(1)
          }
        }
      }
      .onHover { hovering = $0 }
      .hoverPopup(isPresented: hovering, theme: theme) {
        VStack(alignment: .leading, spacing: 4) {
          if r.sessions.isEmpty { Text("No sessions").foregroundStyle(theme.palette.text2) }
          ForEach(r.sessions) { s in
            HStack(spacing: 6) {
              Circle().fill(Self.color(for: s.state, theme: theme)).frame(width: 7, height: 7)
              Text(s.label).font(.headline).foregroundStyle(theme.palette.text)
              Text(Self.detail(for: s)).font(.caption).foregroundStyle(theme.palette.text3).lineLimit(1)
            }
          }
        }
      }
    }
  }

  /// The chip's label and tint. A session waiting on the user wins over the plain count.
  nonisolated static func describe(_ r: RexState, clip: Int, showCount: Bool) -> (label: String?, tint: AccentToken?) {
    if let first = r.attention.first {
      var label = Self.clip(first.label, clip)
      switch first.state {
      case .blocked: label += first.kind == "permission" ? " · approve" : " · waiting"
      default: label += " · failed"
      }
      let extra = r.attention.count - 1
      if extra > 0 { label += " +\(extra)" }
      return (label, first.state == .blocked ? .peach : .red)
    }
    let working = r.sessions.contains { $0.state == .working }
    return (showCount ? "\(r.sessions.count)" : nil, working ? .blue : nil)
  }

  nonisolated static func clip(_ s: String, _ clip: Int) -> String {
    let c = max(4, clip)
    return s.count > c ? String(s.prefix(c - 1)) + "…" : s
  }

  nonisolated static func detail(for s: RexSession) -> String {
    let panes = s.blocks == 1 ? "1 pane" : "\(s.blocks) panes"
    let what: String
    switch s.state {
    case .idle: return panes
    case .blocked: what = s.kind == "permission" ? "needs approval" : "waiting"
    case .error: what = "failed"
    case .working: what = "working"
    case .done: what = "done"
    }
    return [s.app, what, s.msg].compactMap { $0 }.joined(separator: " · ")
  }

  static func color(for state: RexSession.State, theme: ResolvedTheme) -> Color {
    switch state {
    case .idle: theme.palette.text3
    case .done: theme.stateColor(.green)
    case .working: theme.stateColor(.blue)
    case .error: theme.stateColor(.red)
    case .blocked: theme.stateColor(.peach)
    }
  }

  private func open(_ r: RexState) {
    if let app = spec.options.clickApp, !app.isEmpty { runtime.open(app: app); return }
    if let s = r.attention.first { runtime.rex.select(s) } else { runtime.rex.activate() }
  }
}
