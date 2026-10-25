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
        RoundedRectangle(cornerRadius: theme.metrics.chipRadius, style: .continuous)
          .fill(theme.palette.highlight.opacity(lit ? 1 : 0))
          .overlay(RoundedRectangle(cornerRadius: theme.metrics.chipRadius, style: .continuous)
            .strokeBorder(theme.palette.highlightRim.opacity(lit ? 1 : 0), lineWidth: 1))
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
