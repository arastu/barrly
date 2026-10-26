import SwiftUI

/// The standard chip: icon + label on a concentric lozenge that lights up on hover
/// ("controls come to life when a person interacts with them").
struct WidgetCell<Content: View>: View {
  var spec: WidgetSpec
  var selected: Bool = false
  var onClick: (() -> Void)? = nil
  var onRightClick: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content

  @Environment(\.theme) private var theme
  @ViewState private var hovered = false

  var body: some View {
    let lit = selected || (hovered && spec.hoverable)
    content()
      .font(theme.fonts.label)
      .foregroundStyle(spec.secondary ? theme.palette.text2 : theme.palette.text)
      .padding(.horizontal, theme.metrics.cellPadding + 4)
      .frame(height: theme.metrics.chipHeight)
      .background {
        let shape = RoundedRectangle(cornerRadius: theme.metrics.chipRadius, style: .continuous)
        if theme.widgetGlass && !theme.reduceTransparency {
          // Every widget rests on its own raised lozenge (glass cannot nest, so this is the hover
          // highlight at half strength with a specular top edge); hover brings it to full.
          shape.fill(theme.palette.highlight.opacity(lit ? 1 : 0.45))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(theme.isDark ? 0.10 : 0.35), .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(theme.palette.highlightRim.opacity(lit ? 1 : 0.55), lineWidth: 1))
        } else {
          shape.fill(theme.palette.highlight.opacity(lit ? 1 : 0))
            .overlay(shape.strokeBorder(theme.palette.highlightRim.opacity(lit ? 1 : 0), lineWidth: 1))
        }
      }
      .animation(theme.hoverAnimation, value: lit)
      .contentShape(Rectangle())
      .onHover { hovered = $0 }
      .onTapGesture { onClick?() }
      .contextMenu { if let onRightClick { Button("Barrly Settings…") { onRightClick() } } }
  }
}

/// Icon + label pair used by most widgets.
struct IconLabel: View {
  var symbol: String? = nil
  var image: NSImage? = nil
  var label: String? = nil
  var iconColor: Color? = nil
  var labelFont: Font? = nil
  @Environment(\.theme) private var theme

  var body: some View {
    HStack(spacing: theme.metrics.iconLabelSpacing) {
      if let image { Image(nsImage: image).resizable().frame(width: 16, height: 16) }
      else if let symbol {
        Image(systemName: symbol).font(theme.fonts.icon).foregroundStyle(iconColor ?? .primary)
          .symbolRenderingMode(.monochrome)
      }
      if let label, !label.isEmpty { Text(label).font(labelFont ?? theme.fonts.label).lineLimit(1) }
    }
  }
}
