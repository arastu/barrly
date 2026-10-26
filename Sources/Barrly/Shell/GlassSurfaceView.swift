import AppKit
import SwiftUI

/// NSHostingView that reports intrinsic-size changes, so the capsule around it can follow.
@MainActor
final class SizingHostingView<Content: View>: NSHostingView<Content> {
  var onIntrinsicSizeChange: ((NSSize) -> Void)? = nil
  override func invalidateIntrinsicContentSize() {
    super.invalidateIntrinsicContentSize()
    onIntrinsicSizeChange?(intrinsicContentSize)
  }
}

/// One Liquid Glass capsule. The glass lives here, inside the glass container, sized to the
/// SwiftUI content; the content itself (`host`) is placed by the window controller in an overlay
/// above the container and kept aligned with this view. That split lets the glass fade towards
/// the backdrop ("clearness") without fading text and icons — NSGlassEffectView composites its
/// contentView together with the glass, so alpha on it would dim everything.
@MainActor
final class GlassSurfaceView: NSView {
  let surfaceID: UUID
  let glass = NSGlassEffectView()
  let host: SizingHostingView<SurfaceView>
  private var widthConstraint: NSLayoutConstraint
  private var heightConstraint: NSLayoutConstraint

  init(surfaceID: UUID, runtime: Runtime) {
    self.surfaceID = surfaceID
    host = SizingHostingView(rootView: SurfaceView(surfaceID: surfaceID, runtime: runtime))
    widthConstraint = NSLayoutConstraint(); heightConstraint = NSLayoutConstraint()
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    postsFrameChangedNotifications = true
    glass.style = .regular
    glass.autoresizingMask = [.width, .height]
    addSubview(glass)
    host.sizingOptions = [.intrinsicContentSize]
    let size = host.intrinsicContentSize
    widthConstraint = widthAnchor.constraint(equalToConstant: max(1, size.width))
    heightConstraint = heightAnchor.constraint(equalToConstant: max(1, size.height))
    NSLayoutConstraint.activate([widthConstraint, heightConstraint])
    host.onIntrinsicSizeChange = { [weak self] s in self?.sync(s) }
  }

  required init?(coder: NSCoder) { fatalError() }

  override func layout() { super.layout(); glass.frame = bounds }

  private func sync(_ s: NSSize) {
    let w = max(1, ceil(s.width)), h = max(1, ceil(s.height))
    if widthConstraint.constant != w { widthConstraint.constant = w }
    if heightConstraint.constant != h { heightConstraint.constant = h }
  }

  func apply(theme: ResolvedTheme, tint: AccentToken?) {
    glass.cornerRadius = theme.metrics.pillRadius
    glass.style = theme.glassStyle == .clear ? .clear : .regular
    if let tint { glass.tintColor = NSColor(theme.palette.accent(tint)).withAlphaComponent(theme.isDark ? 0.22 : 0.18) } else { glass.tintColor = nil }
    // 0 = full system glass, 1 = almost gone (the backdrop shows through unrefracted).
    glass.alphaValue = 1 - 0.9 * min(1, max(0, theme.glassClearness))
    sync(host.intrinsicContentSize)
  }
}

/// Transparent layer above the glass container holding the capsules' SwiftUI content.
/// Empty areas let events through to nothing (the bar never activates anyway).
final class ContentOverlayView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    let v = super.hitTest(point)
    return v === self ? nil : v
  }
}
