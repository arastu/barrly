import AppKit
import SwiftUI

/// Shown only while a VPN is connected. Hover lists every active tunnel; click opens the VPN settings.
struct VPNWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var hovering = false

  var body: some View {
    let v = runtime.vpn.state
    if let first = v.connections.first {
      let label = Self.label(first.name, extra: v.connections.count - 1, clip: spec.options.clipChars)
      WidgetCell(spec: spec, onClick: { open() }) {
        IconLabel(symbol: "lock.shield.fill", label: spec.options.showName ? label : nil, iconColor: theme.iconTint(for: spec))
      }
      .onHover { hovering = $0 }
      .hoverPopup(isPresented: hovering, theme: theme) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(v.connections) { c in
            HStack(spacing: 6) {
              Image(systemName: "checkmark.shield.fill").foregroundStyle(theme.stateColor(.green))
              Text(c.name).font(.headline).foregroundStyle(theme.palette.text)
              Text(c.kind).font(.caption).foregroundStyle(theme.palette.text3)
            }
          }
        }
      }
    }
  }

  static func label(_ name: String, extra: Int, clip: Int) -> String {
    let clip = max(1, clip)
    var label = name
    if extra > 0 { label += " +\(extra)" }
    if label.count > clip { label = String(label.prefix(clip - 1)) + "…" }
    return label
  }

  private func open() {
    if let app = spec.options.clickApp, !app.isEmpty { runtime.open(app: app); return }
    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?VPN") { NSWorkspace.shared.open(url) }
  }
}
