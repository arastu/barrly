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

/// One capsule hosting a SwiftUI SurfaceView. With a system glass style the content sits inside an
/// NSGlassEffectView; with the transparent style the glass is bypassed and SurfaceView draws its own
/// see-through capsule. Width follows the SwiftUI content: NSGlassEffectView manages its own
/// contentView, so the capsule is sized explicitly instead of through constraints crossing into it.
@MainActor
final class GlassSurfaceView: NSView {
  let surfaceID: UUID
  private let glass = NSGlassEffectView()
  private let host: SizingHostingView<SurfaceView>
  private var widthConstraint: NSLayoutConstraint
  private var heightConstraint: NSLayoutConstraint

  init(surfaceID: UUID, runtime: Runtime) {
    self.surfaceID = surfaceID
    host = SizingHostingView(rootView: SurfaceView(surfaceID: surfaceID, runtime: runtime))
    widthConstraint = NSLayoutConstraint(); heightConstraint = NSLayoutConstraint()
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    glass.style = .regular
    glass.autoresizingMask = [.width, .height]
    addSubview(glass)
    host.sizingOptions = [.intrinsicContentSize]
    host.autoresizingMask = [.width, .height]
    glass.contentView = host
    let size = host.intrinsicContentSize
    widthConstraint = widthAnchor.constraint(equalToConstant: max(1, size.width))
    heightConstraint = heightAnchor.constraint(equalToConstant: max(1, size.height))
    NSLayoutConstraint.activate([widthConstraint, heightConstraint])
    host.onIntrinsicSizeChange = { [weak self] s in self?.sync(s) }
  }

  required init?(coder: NSCoder) { fatalError() }

  override func layout() {
    super.layout()
    glass.frame = bounds
    if host.superview === self { host.frame = bounds }
  }

  private func sync(_ s: NSSize) {
    let w = max(1, ceil(s.width)), h = max(1, ceil(s.height))
    if widthConstraint.constant != w { widthConstraint.constant = w }
    if heightConstraint.constant != h { heightConstraint.constant = h }
  }

  func apply(theme: ResolvedTheme, tint: AccentToken?) {
    if theme.glassStyle == .transparent {
      // No system glass: the content hosts its own see-through capsule.
      if host.superview !== self { glass.contentView = nil; addSubview(host); host.frame = bounds }
      glass.isHidden = true
    } else {
      if glass.contentView !== host { host.removeFromSuperview(); glass.contentView = host }
      glass.isHidden = false
      glass.style = theme.glassStyle == .clear ? .clear : .regular
      glass.cornerRadius = theme.metrics.pillRadius
      if let tint { glass.tintColor = NSColor(theme.palette.accent(tint)).withAlphaComponent(theme.isDark ? 0.22 : 0.18) } else { glass.tintColor = nil }
    }
    sync(host.intrinsicContentSize)
  }
}
