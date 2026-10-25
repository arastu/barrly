import SwiftUI

/// One cell per AeroSpace workspace: id + app icons of its windows. Focused = raised lozenge.
struct WorkspacesWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme

  var body: some View {
    let a = runtime.aerospace
    HStack(spacing: 2) {
      ForEach(a.workspaces) { ws in
        let occupied = !ws.windows.isEmpty
        if ws.isFocused || occupied || !spec.options.hideEmpty {
          WorkspaceCell(spec: spec, workspace: ws, focused: ws.isFocused, occupied: occupied) { runtime.aerospace.focus(workspace: ws.id) }
        }
      }
    }
    .animation(theme.stateAnimation, value: a.workspaces.map(\.id))
  }
}

private struct WorkspaceCell: View {
  let spec: WidgetSpec
  let workspace: AeroWorkspace
  let focused: Bool
  let occupied: Bool
  let onClick: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    var cellSpec = spec; cellSpec.secondary = !focused
    return WidgetCell(spec: cellSpec, selected: focused, onClick: onClick) {
      HStack(spacing: 4) {
        if spec.options.showIds { Text(workspace.id).font(theme.fonts.label) }
        ForEach(Array(workspace.bundleIds.prefix(spec.options.maxIcons)), id: \.self) { bid in
          if let img = AppIconCache.shared.icon(bundleId: bid, size: 16) {
            Image(nsImage: img).resizable().frame(width: 16, height: 16).opacity(focused ? 1 : 0.75)
          }
        }
      }
      .padding(.horizontal, 2)
    }
  }
}
