import AppKit
import SwiftUI

/// A small non-activating glass panel anchored under a bar item (meeting details, etc.).
/// Deliberately NOT a child window of the bar: child windows inherit the parent's level, and the
/// bar sits below normal windows. This panel floats at pop-up-menu level, above everything.
@MainActor
final class PopupPanel {
  /// Hover popups (one at a time).
  static let shared = PopupPanel()
  /// The Claude Code session list, opened by a click; its own panel so a hover popup doesn't replace it.
  static let sessions = PopupPanel()
  private var panel: NSPanel? = nil
  private var hosted: NSHostingView<AnyView>? = nil
  private var monitors: [Any] = []
  private var anchor: CGRect = .zero

  var isVisible: Bool { panel?.isVisible ?? false }
  /// Which chip opened the panel, so a click on it closes the panel and a click on another chip swaps the content.
  private(set) var owner: UUID? = nil

  /// Click on a chip: closes the panel if this chip opened it, otherwise shows `content` under `anchor`.
  func toggle<V: View>(owner id: UUID, _ content: V, anchor: CGRect, parent: NSWindow?, theme: ResolvedTheme) {
    if isVisible, owner == id { hide(); return }
    owner = id
    show(content, anchor: anchor, parent: parent, theme: theme, untilClickedOutside: true, sizedByContent: false)
  }

  /// Shows `content` under `anchor` (screen coordinates). With `untilClickedOutside`, the panel stays
  /// until a click lands outside it (a click on the anchor is left to the anchor, which toggles).
  /// `sizedByContent`: the panel takes the content's intrinsic size (hover popups). A list panel
  /// passes false: it reports its measured size through `resize(to:)` instead, because a hosting
  /// view with the intrinsic-size option resizes itself to its content.
  func show<V: View>(_ content: V, anchor: CGRect, parent: NSWindow?, theme: ResolvedTheme,
                     untilClickedOutside: Bool = false, sizedByContent: Bool = true) {
    // Glass is drawn by SwiftUI; the hosting view fills a plain container that is the panel's content
    // view (a hosting view nested in an NSGlassEffectView kept stale sizes).
    let rooted = AnyView(content.environment(\.theme, theme)
      .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous)))
    let host: NSHostingView<AnyView>
    if let hosted { host = hosted; host.rootView = rooted }
    else { host = NSHostingView(rootView: rooted); hosted = host }
    // Measure the content with the intrinsic-size option, then size the panel explicitly.
    host.sizingOptions = [.intrinsicContentSize]
    let size = sizedByContent ? host.intrinsicContentSize : CGSize(width: 340, height: 40)
    host.sizingOptions = []
    let p: NSPanel
    if let panel { p = panel } else {
      p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
      p.level = .popUpMenu; p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      p.isReleasedWhenClosed = false; p.animationBehavior = .utilityWindow
      // Hover highlights without activating: a non-key window gets mouse-moved events only on request.
      p.acceptsMouseMovedEvents = true
      // The hosting view must not be the panel's content view: in that role it manages the window's
      // size extrema from its own constraints pass, and on macOS 27 that re-enters the pass until
      // AppKit raises, killing the app the moment a hover popup opens.
      let container = NSView()
      host.autoresizingMask = [.width, .height]
      container.addSubview(host)
      p.contentView = container
      panel = p
    }
    self.anchor = anchor
    p.setFrame(frame(for: size), display: true)
    host.frame = p.contentView?.bounds ?? .zero
    _ = parent
    p.orderFrontRegardless()
    removeMonitors()
    if untilClickedOutside { watchForOutsideClicks() }
  }

  /// Follows the content when its size changes (the list grows or shrinks).
  func resize(to size: CGSize) {
    guard let panel, panel.isVisible, panel.frame.size != size else { return }
    panel.setFrame(frame(for: size), display: true)
  }

  /// Centred under the anchor, kept inside the anchor's screen.
  private func frame(for size: CGSize) -> CGRect {
    var x = anchor.midX - size.width / 2
    let y = anchor.minY - size.height - 6
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main {
      let v = screen.visibleFrame
      x = min(max(x, v.minX + 8), max(v.minX + 8, v.maxX - size.width - 8))
    }
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  private func watchForOutsideClicks() {
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
      Task { @MainActor [weak self] in self?.clickedOutside(at: NSEvent.mouseLocation) }
    }) { monitors.append(m) }
    if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
      MainActor.assumeIsolated {
        guard let self, event.window !== self.panel else { return }
        self.clickedOutside(at: NSEvent.mouseLocation)
      }
      return event
    }) { monitors.append(m) }
  }

  private func clickedOutside(at point: CGPoint) {
    guard let panel, panel.isVisible, !panel.frame.contains(point), !anchor.contains(point) else { return }
    hide()
  }

  private func removeMonitors() { monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll() }

  func hide() { removeMonitors(); owner = nil; panel?.orderOut(nil) }
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

struct AnchorView: NSViewRepresentable {
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
