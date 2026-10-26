import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let runtime = Runtime()
  private var displays: DisplayManager? = nil
  private var signalSources: [DispatchSourceSignal] = []
  private let log = Logger(subsystem: "dev.barrly", category: "app")
  /// Bundle of an already running Barrly (e.g. the Homebrew copy launched by a barrly:// URL while a
  /// dev build runs). This instance then forwards its URLs to it and quits instead of drawing a second bar.
  private var runningInstance: URL? = nil

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let me = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.barrly.app")
      .filter { $0.processIdentifier != me && !$0.isTerminated }
    runningInstance = others.first?.bundleURL
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let runningInstance {
      log.notice("another Barrly is running at \(runningInstance.path); quitting")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
      return
    }
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
    if let runningInstance {
      NSWorkspace.shared.open(urls, withApplicationAt: runningInstance, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
        Task { @MainActor in NSApp.terminate(nil) }
      }
      return
    }
    for url in urls { runtime.handle(url: url) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    runtime.showSettings(); return false
  }
}
