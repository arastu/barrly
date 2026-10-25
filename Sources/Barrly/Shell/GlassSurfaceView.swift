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

/// One Liquid Glass capsule hosting a SwiftUI SurfaceView. Width follows the SwiftUI content:
/// NSGlassEffectView manages its contentView itself, so we size the glass view explicitly
/// instead of relying on constraints crossing into it.
@MainActor
final class GlassSurfaceView: NSGlassEffectView {
  let surfaceID: UUID
  private let host: SizingHostingView<SurfaceView>
  private var widthConstraint: NSLayoutConstraint
  private var heightConstraint: NSLayoutConstraint

  init(surfaceID: UUID, runtime: Runtime) {
    self.surfaceID = surfaceID
    host = SizingHostingView(rootView: SurfaceView(surfaceID: surfaceID, runtime: runtime))
    widthConstraint = NSLayoutConstraint(); heightConstraint = NSLayoutConstraint()
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    host.sizingOptions = [.intrinsicContentSize]
    host.autoresizingMask = [.width, .height]
    style = .regular
    contentView = host
    let size = host.intrinsicContentSize
    widthConstraint = widthAnchor.constraint(equalToConstant: max(1, size.width))
    heightConstraint = heightAnchor.constraint(equalToConstant: max(1, size.height))
    NSLayoutConstraint.activate([widthConstraint, heightConstraint])
    host.onIntrinsicSizeChange = { [weak self] s in self?.sync(s) }
  }

  required init?(coder: NSCoder) { fatalError() }

  private func sync(_ s: NSSize) {
    let w = max(1, ceil(s.width)), h = max(1, ceil(s.height))
    if widthConstraint.constant != w { widthConstraint.constant = w }
    if heightConstraint.constant != h { heightConstraint.constant = h }
  }

  func apply(theme: ResolvedTheme, tint: AccentToken?) {
    cornerRadius = theme.metrics.pillRadius
    if let tint { tintColor = NSColor(theme.palette.accent(tint)).withAlphaComponent(theme.isDark ? 0.22 : 0.18) } else { tintColor = nil }
    sync(host.intrinsicContentSize)
  }
}
