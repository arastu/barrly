import AppKit
import Observation

/// One bar per screen; rebuilt when displays change or the display selection setting changes.
@MainActor
final class DisplayManager {
  private let runtime: Runtime
  private var controllers: [BarWindowController] = []
  private var token: NSObjectProtocol? = nil
  private var rebuildTask: Task<Void, Never>? = nil

  init(runtime: Runtime) {
    self.runtime = runtime
    token = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
      Task { @MainActor [weak self] in self?.scheduleRebuild() }
    }
    observe()
  }

  private func observe() {
    withObservationTracking {
      _ = runtime.settings.settings.appearance.displays
    } onChange: {
      Task { @MainActor [weak self] in self?.scheduleRebuild(); self?.observe() }
    }
    rebuild()
  }

  private func scheduleRebuild() {
    rebuildTask?.cancel()
    rebuildTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      self?.rebuild()
    }
  }

  private func rebuild() {
    let screens: [NSScreen] = switch runtime.settings.settings.appearance.displays {
      case .all: NSScreen.screens
      case .main: [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
    }
    // Reuse controllers whose screen still exists; close the rest.
    var next: [BarWindowController] = []
    for screen in screens {
      if let existing = controllers.first(where: { $0.screenID == screen.displayID }) { existing.attach(to: screen); next.append(existing) }
      else { next.append(BarWindowController(runtime: runtime, screen: screen)) }
    }
    for c in controllers where !next.contains(where: { $0 === c }) { c.close() }
    controllers = next
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? 0
  }
}
