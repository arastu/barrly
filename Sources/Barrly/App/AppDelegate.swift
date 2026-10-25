import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = Runtime()
  private var displays: DisplayManager? = nil
  private var signalSources: [DispatchSourceSignal] = []
  private let log = Logger(subsystem: "dev.barrly", category: "app")

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    displays = DisplayManager(runtime: runtime)
    // SIGTERM / SIGINT (pkill, brew services stop) bypass applicationWillTerminate; make sure the
    // now-playing helper process dies with us.
    for sig in [SIGTERM, SIGINT, SIGHUP] {
      signal(sig, SIG_IGN)
      let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      src.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
      src.resume(); signalSources.append(src)
    }
    if let err = runtime.settings.loadError { log.error("settings failed to load, using defaults: \(err)") }
    log.info("Barrly started")
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtime.shutdown()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { runtime.handle(url: url) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    runtime.showSettings(); return false
  }
}
