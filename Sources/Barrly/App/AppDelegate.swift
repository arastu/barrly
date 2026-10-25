import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = Runtime()
  private var displays: DisplayManager? = nil
  private let log = Logger(subsystem: "dev.barrly", category: "app")

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    displays = DisplayManager(runtime: runtime)
    if let err = runtime.settings.loadError { log.error("settings failed to load, using defaults: \(err)") }
    log.info("Barrly started")
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { runtime.handle(url: url) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    runtime.showSettings(); return false
  }
}
