import SwiftUI

/// Tea-style list panel (github.com/ianiv/tea), opened by a click on a chip: a title row with a
/// button to Barrly's settings, an optional error line, scrolling sections of cards, a notice at
/// the bottom. Sized to its content, up to Tea's 340 × 600; `PopupPanel.sessions` follows.
struct ListPanel<Content: View>: View {
  static var width: CGFloat { 340 }
  static var maxHeight: CGFloat { 600 }
  let title: String
  var error: String? = nil
  var notice: String? = nil
  var isEmpty: Bool
  var emptyText: String
  var emptySymbol: String = "sparkles"
  /// The sections: a `LazyVStack` with pinned section headers, so its height is the content height.
  @ViewBuilder let content: () -> Content

  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var chromeHeight: CGFloat = 0
  @ViewState private var listHeight: CGFloat = 0
  @ViewState private var footerHeight: CGFloat = 0

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Text(title).font(.headline).foregroundStyle(theme.palette.text)
          Spacer()
          Button { PopupPanel.sessions.hide(); runtime.showSettings() } label: {
            Image(systemName: "slider.horizontal.3").foregroundStyle(theme.palette.text2)
          }
          .buttonStyle(.plain)
          .help("Options, in Barrly's settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        Divider()
        if let error {
          Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(theme.stateColor(.red))
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
      if isEmpty && error == nil {
        VStack(spacing: 6) {
          Image(systemName: emptySymbol).font(.title).foregroundStyle(theme.palette.text3)
          Text(emptyText).font(.headline).foregroundStyle(theme.palette.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
      } else {
        ScrollView {
          content()
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
      }
      if let notice {
        VStack(spacing: 0) {
          Divider()
          Text(notice).font(.caption).foregroundStyle(theme.palette.text2).padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
      }
    }
    .frame(width: Self.width, height: min(Self.maxHeight, chromeHeight + listHeight + (notice == nil ? 0 : footerHeight)))
    // A long list sits over whatever window is below; a backing tint keeps it readable on the glass.
    .background(theme.palette.popup.opacity(0.75))
    .onGeometryChange(for: CGSize.self) { $0.size } action: { PopupPanel.sessions.resize(to: $0) }
  }
}

/// A section header: chevron, state dot, title, count. Click collapses the section.
struct ListSectionHeader: View {
  let title: String
  let count: Int
  var color: Color? = nil
  let collapsed: Bool
  let toggle: () -> Void
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.palette.text2)
          .rotationEffect(.degrees(collapsed ? 0 : 90)).frame(width: 10)
        Circle().fill(color ?? theme.palette.text3).frame(width: 7, height: 7)
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.palette.text)
        Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(theme.palette.text2)
        Spacer()
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(theme.palette.popup)
    .help(collapsed ? "Show \(title)" : "Hide \(title)")
  }
}

/// A card: a state icon on the left, the title row (name, trailing text) and the lines below.
struct ListCard<Lines: View>: View {
  let symbol: String
  var color: Color? = nil
  let title: String
  var trailing: String = ""
  var help: String = ""
  @ViewBuilder let lines: () -> Lines
  @Environment(\.theme) private var theme
  @ViewState private var hovering = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(color ?? theme.palette.text2)
        .font(.system(size: 15, weight: .semibold)).frame(width: 18).padding(.top, 1)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(title).font(.system(.body, weight: .semibold)).foregroundStyle(theme.palette.text).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 6)
          if !trailing.isEmpty { Text(trailing).font(.caption).foregroundStyle(theme.palette.text2).monospacedDigit() }
        }
        lines()
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.palette.highlight.opacity(hovering ? 1 : 0)))
    .animation(theme.hoverAnimation, value: hovering)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .help(help)
  }
}
