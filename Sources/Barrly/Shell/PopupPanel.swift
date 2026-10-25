import AppKit
import SwiftUI

/// A small non-activating glass panel anchored under a bar item (meeting details, etc.).
/// Child of the bar panel so it follows it across displays and Spaces; never takes focus.
@MainActor
final class PopupPanel {
  static let shared = PopupPanel()
  private var panel: NSPanel? = nil
  private var hosted: NSHostingView<AnyView>? = nil
  private var token: Any? = nil

  func show<V: View>(_ content: V, anchor: CGRect, parent: NSWindow?, theme: ResolvedTheme) {
    let host: NSHostingView<AnyView>
    if let hosted { host = hosted; host.rootView = AnyView(content.environment(\.theme, theme)) }
    else { host = NSHostingView(rootView: AnyView(content.environment(\.theme, theme))); hosted = host }
    host.sizingOptions = [.intrinsicContentSize]
    let size = host.intrinsicContentSize
    let p: NSPanel
    if let panel { p = panel } else {
      p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
      p.level = .popUpMenu; p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      p.isReleasedWhenClosed = false; p.animationBehavior = .utilityWindow
      let glass = NSGlassEffectView(); glass.style = .regular; glass.cornerRadius = 14
      glass.contentView = host; host.autoresizingMask = [.width, .height]
      p.contentView = glass
      panel = p
    }
    let x = anchor.midX - size.width / 2
    let y = anchor.minY - size.height - 6
    p.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    if let parent, p.parent !== parent { p.parent?.removeChildWindow(p); parent.addChildWindow(p, ordered: .above) }
    p.orderFrontRegardless()
  }

  func hide() { if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) } }
}

/// Reports the on-screen frame of the view it is attached to.
private struct ScreenFrameReader: NSViewRepresentable {
  var onChange: (CGRect, NSWindow?) -> Void
  func makeNSView(context: Context) -> TrackerView { let v = TrackerView(); v.onChange = onChange; return v }
  func updateNSView(_ v: TrackerView, context: Context) { v.onChange = onChange; v.report() }
  final class TrackerView: NSView {
    var onChange: ((CGRect, NSWindow?) -> Void)? = nil
    override func layout() { super.layout(); report() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
    func report() {
      guard let window else { return }
      let rect = window.convertToScreen(convert(bounds, to: nil))
      onChange?(rect, window)
    }
  }
}

extension View {
  /// Shows `content` in a floating glass panel under this view while `isPresented` is true.
  func hoverPopup<V: View>(isPresented: Bool, theme: ResolvedTheme, @ViewBuilder content: @escaping () -> V) -> some View {
    modifier(HoverPopupModifier(isPresented: isPresented, theme: theme, content: content))
  }
}

private struct HoverPopupModifier<V: View>: ViewModifier {
  var isPresented: Bool
  var theme: ResolvedTheme
  var content: () -> V
  @ViewState private var frame: CGRect = .zero
  @ViewState private var window: NSWindow? = nil

  func body(content base: Content) -> some View {
    base
      .background(ScreenFrameReader { r, w in frame = r; window = w })
      .onChange(of: isPresented) { _, on in
        if on { PopupPanel.shared.show(content().padding(14), anchor: frame, parent: window, theme: theme) } else { PopupPanel.shared.hide() }
      }
      .onDisappear { if isPresented { PopupPanel.shared.hide() } }
  }
}
