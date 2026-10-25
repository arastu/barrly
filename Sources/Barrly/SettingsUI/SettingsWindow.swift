import AppKit
import SwiftUI

/// Barrly's settings window. The app is an accessory (no Dock icon, no menu bar), so it owns
/// the window itself instead of going through the SwiftUI Settings scene.
@MainActor
final class SettingsWindowController {
  static let shared = SettingsWindowController()
  private var window: NSWindow? = nil

  func show(runtime: Runtime) {
    if window == nil {
      let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
      w.title = "Barrly Settings"
      w.titlebarAppearsTransparent = false
      w.contentView = NSHostingView(rootView: SettingsView().environment(runtime))
      w.isReleasedWhenClosed = false
      w.center()
      w.setFrameAutosaveName("BarrlySettings")
      window = w
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}
