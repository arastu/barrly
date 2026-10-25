import AppKit
import SwiftUI

/// A small non-activating glass panel anchored under a bar item (meeting details, etc.).
/// Deliberately NOT a child window of the bar: child windows inherit the parent's level, and the
/// bar sits below normal windows. This panel floats at pop-up-menu level, above everything.
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
    _ = parent
    p.orderFrontRegardless()
  }

  func hide() { panel?.orderOut(nil) }
}

/// Keeps a handle to an invisible NSView inside the SwiftUI hierarchy so the on-screen frame
/// of the host view can be read at the moment it is needed (after layout), not when attached.
@MainActor
final class AnchorBox {
  weak var view: NSView? = nil
  var screenFrame: CGRect? {
    guard let view, let window = view.window else { return nil }
    return window.convertToScreen(view.convert(view.bounds, to: nil))
  }
  var window: NSWindow? { view?.window }
}

private struct AnchorView: NSViewRepresentable {
  let box: AnchorBox
  func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
  func updateNSView(_ v: NSView, context: Context) { box.view = v }
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
  @ViewState private var box = AnchorBox()

  func body(content base: Content) -> some View {
    base
      .background(AnchorView(box: box))
      .onChange(of: isPresented) { _, on in
        if on, let frame = box.screenFrame {
          PopupPanel.shared.show(content().padding(14), anchor: frame, parent: box.window, theme: theme)
        } else {
          PopupPanel.shared.hide()
        }
      }
      .onDisappear { if isPresented { PopupPanel.shared.hide() } }
  }
}
