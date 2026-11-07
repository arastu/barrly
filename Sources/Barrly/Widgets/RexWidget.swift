import AppKit
import SwiftUI

/// Rex sessions, shown while Rex runs: the session count, or the session a program is waiting on
/// (OSC 7501 blocked / error), with the count of other agents waiting. Click
/// opens the list, like Rex's own block switcher: every session, and under it every pane with the
/// process running in it; a pane in the list opens in Rex.
struct RexWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var box = AnchorBox()

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
      .background(AnchorView(box: box))
      .onDisappear { if PopupPanel.sessions.owner == spec.id { PopupPanel.sessions.hide() } }
    }
  }

  /// The chip's label and tint. A session waiting on the user wins, with how many more agents are
  /// waiting; otherwise the plain session count. (Working is the Claude Code widget's business.)
  nonisolated static func describe(_ r: RexState, clip: Int, showCount: Bool) -> (label: String?, tint: AccentToken?) {
    if let first = r.attention.first {
      var label = Self.clip(first.label, clip)
      switch first.state {
      case .blocked: label += first.kind == "permission" ? " · approve" : " · waiting"
      default: label += " · failed"
      }
      // Other agents waiting on the user (in this session or another), or else other sessions needing attention.
      let extra = max(first.state == .blocked ? r.blocked - 1 : 0, r.attention.count - 1)
      if extra > 0 { label += " +\(extra)" }
      return (label, first.state == .blocked ? .peach : .red)
    }
    return (showCount ? "\(r.sessions.count)" : nil, nil)
  }

  nonisolated static func clip(_ s: String, _ clip: Int) -> String {
    let c = max(4, clip)
    return s.count > c ? String(s.prefix(c - 1)) + "…" : s
  }

  /// Panes, and agents when there are any.
  nonisolated static func panes(for s: RexSession) -> String {
    var panes = s.blocks == 1 ? "1 pane" : "\(s.blocks) panes"
    if s.agents > 0 { panes += s.agents == 1 ? " · 1 agent" : " · \(s.agents) agents" }
    return panes
  }

  /// What a program reports, as the row says it. Nil for idle: an idle shell says nothing.
  nonisolated static func word(for state: RexSession.State, kind: String? = nil) -> String? {
    switch state {
    case .idle: nil
    case .blocked: kind.map { "Needs \($0)" } ?? "Waiting for you"
    case .error: "Failed"
    case .working: "Working"
    case .done: "Done"
    }
  }

  nonisolated static func word(for s: RexSession) -> String { word(for: s.state, kind: s.kind) ?? "Idle" }

  nonisolated static let shells: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "nu", "tcsh", "csh", "ksh", "login"]

  nonisolated static func isShell(_ name: String?) -> Bool { name.map { shells.contains($0) } ?? false }

  /// The row's name for a process.
  nonisolated static func displayName(_ name: String?) -> String {
    switch name {
    case nil: "pane"
    case "claude": "Claude Code"
    case "nvim": "Neovim"
    case "vim", "vi": "Vim"
    case "hx": "Helix"
    case "emacs": "Emacs"
    case "codex": "Codex"
    case "gemini": "Gemini CLI"
    case "aider": "Aider"
    case "opencode": "OpenCode"
    case "node": "Node"
    case "python", "python3": "Python"
    case "cargo": "Cargo"
    case "ssh": "SSH"
    case "git": "Git"
    case let n?: n
    }
  }

  /// The grey text after the name: a shell shows where it is; another program shows the title it
  /// set (Claude Code's task, an editor's file), else where it is.
  nonisolated static func secondary(for pane: RexPane, home: String = NSHomeDirectory()) -> String? {
    let cwd = pane.cwd.map { ClaudeProvider.shortPath($0, home: home) }
    if isShell(pane.name) { return cwd }
    if let title = pane.title, !title.isEmpty, title != displayName(pane.name), pane.titlePid == nil || pane.titlePid == pane.pid { return title }
    return cwd
  }

  /// Collapsed sections are keyed by a hash of the session id that is stable across launches.
  nonisolated static func stableKey(_ s: String) -> Int {
    var h: UInt32 = 5381
    for b in s.utf8 { h = h &* 33 &+ UInt32(b) }
    return Int(h & 0x7fff_ffff)
  }

  nonisolated static func symbol(for state: RexSession.State) -> String {
    switch state {
    case .blocked: "exclamationmark.circle.fill"
    case .error: "xmark.octagon.fill"
    case .working: "ellipsis"
    case .done: "checkmark"
    case .idle: "circle"
    }
  }

  static func color(for state: RexSession.State, theme: ResolvedTheme) -> Color? {
    switch state {
    case .idle: nil
    case .done: theme.stateColor(.green)
    case .working: theme.stateColor(.blue)
    case .error: theme.stateColor(.red)
    case .blocked: theme.stateColor(.peach)
    }
  }

  private func open(_ r: RexState) {
    if let app = spec.options.clickApp, !app.isEmpty { runtime.open(app: app); return }
    guard let frame = box.screenFrame else { return }
    PopupPanel.sessions.toggle(owner: spec.id, RexSessionsView(specID: spec.id).environment(runtime), anchor: frame, parent: box.window, theme: theme)
  }
}

/// The list: one section per session, one row per pane; a row opens that pane in Rex.
struct RexSessionsView: View {
  let specID: UUID
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme

  var body: some View {
    let r = runtime.rex.state
    let collapsed = Set(runtime.settings.spec(id: specID)?.options.collapsedSections ?? [])
    ListPanel(title: "Rex", error: r.connected ? nil : (runtime.rex.lastError ?? "Rex isn't running"),
              isEmpty: r.sessions.isEmpty, emptyText: "No sessions", emptySymbol: "terminal") {
      TimelineView(.periodic(from: .now, by: 30)) { context in
        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
          ForEach(r.sessions) { s in
            let key = RexWidget.stableKey(s.id)
            let hidden = collapsed.contains(key)
            Section {
              if !hidden {
                if s.panes.isEmpty {
                  // An older watcher sends no panes: one row for the session itself.
                  Button { PopupPanel.sessions.hide(); runtime.rex.select(s) } label: {
                    RexPaneRow(pane: RexPane(block: s.id, name: nil, state: s.state, app: s.app, kind: s.kind, msg: s.msg),
                               fallbackName: RexWidget.panes(for: s), now: context.date)
                  }
                  .buttonStyle(.plain).padding(.horizontal, 8)
                }
                ForEach(s.panes) { pane in
                  // Like Rex's switcher, the list closes once Rex comes forward on the pane.
                  Button { PopupPanel.sessions.hide(); runtime.rex.select(block: pane.block, window: pane.window, in: s.id) } label: {
                    RexPaneRow(pane: pane, now: context.date)
                  }
                  .buttonStyle(.plain)
                  .padding(.horizontal, 8)
                }
              }
            } header: {
              ListSectionHeader(title: s.label, count: s.panes.isEmpty ? s.blocks : s.panes.count,
                                color: RexWidget.color(for: s.state, theme: theme), collapsed: hidden) {
                withAnimation(theme.hoverAnimation) { toggleCollapsed(key) }
              }
            }
          }
        }
      }
    }
  }

  private func toggleCollapsed(_ key: Int) {
    runtime.settings.update(specID) { spec in
      if let i = spec.options.collapsedSections.firstIndex(of: key) { spec.options.collapsedSections.remove(at: i) }
      else { spec.options.collapsedSections.append(key); spec.options.collapsedSections.sort() }
    }
  }
}

/// One pane: the process's icon, its name with where it is or its title, and on the right what it
/// reports: working, waiting, failed, done, or idle for how long.
struct RexPaneRow: View {
  let pane: RexPane
  var fallbackName: String? = nil
  let now: Date
  @Environment(\.theme) private var theme
  @ViewState private var hovering = false

  var body: some View {
    let color = RexWidget.color(for: pane.state, theme: theme)
    HStack(spacing: 10) {
      RexProcessIcon(name: pane.name)
      HStack(spacing: 5) {
        Text(fallbackName ?? RexWidget.displayName(pane.name)).font(.system(.body, weight: .medium)).foregroundStyle(theme.palette.text).lineLimit(1)
        if let secondary = RexWidget.secondary(for: pane) {
          Text(secondary).font(.body).foregroundStyle(theme.palette.text2).lineLimit(1).truncationMode(.middle)
        }
      }
      Spacer(minLength: 8)
      status(color: color)
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 10)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.palette.highlight.opacity(hovering ? 1 : 0)))
    .animation(theme.hoverAnimation, value: hovering)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .help(pane.msg ?? "Go to this pane in Rex")
  }

  @ViewBuilder private func status(color: Color?) -> some View {
    switch pane.state {
    case .working, .done:
      Image(systemName: RexWidget.symbol(for: pane.state)).font(.body.weight(.semibold)).foregroundStyle(color ?? theme.palette.text2)
    case .blocked, .error:
      Text(RexWidget.word(for: pane.state, kind: pane.kind) ?? "").font(.caption).foregroundStyle(color ?? theme.palette.text2).lineLimit(1)
    case .idle:
      // Only a program that reported a status is "idle"; a plain shell says nothing.
      if pane.app != nil {
        Text("Idle" + (pane.updatedAt.map { " " + ClaudeProvider.age(from: $0, to: now) } ?? "")).font(.caption).foregroundStyle(theme.palette.text2)
      }
    }
  }
}

/// A 20 pt badge: the Claude app icon for Claude Code, a terminal glyph for a shell, a monogram otherwise.
struct RexProcessIcon: View {
  let name: String?
  @Environment(\.theme) private var theme

  var body: some View {
    if name == "claude", let icon = AppIconCache.shared.icon(bundleId: ClaudeWidget.claudeAppBundleID, size: 20) {
      Image(nsImage: icon).resizable().frame(width: 20, height: 20)
    } else {
      let shell = RexWidget.isShell(name)
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(shell ? Color(white: theme.isDark ? 0.22 : 0.30) : theme.stateColor(.sapphire).opacity(0.85))
        .frame(width: 20, height: 20)
        .overlay {
          if shell {
            Image(systemName: "terminal").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.stateColor(.green))
          } else {
            Text(String(RexWidget.displayName(name).prefix(1)).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
          }
        }
    }
  }
}
