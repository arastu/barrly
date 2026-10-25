import AppKit

/// Borderless, non-activating panel: clicks never steal focus from the front app.
final class BarPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init(frame: CGRect) {
    super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isFloatingPanel = true
    hidesOnDeactivate = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    isMovableByWindowBackground = false
    animationBehavior = .none
    isReleasedWhenClosed = false
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
  }

  /// Default: just above the desktop, below app windows (backstop menu level).
  /// Always on top: floating level — above app windows but still below the system menu bar,
  /// so an auto-hidden menu bar can slide over the bar when revealed.
  func apply(topmost: Bool) {
    level = topmost ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
  }
}
