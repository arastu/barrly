import AppKit
import Observation

struct FrontApp: Hashable, Sendable {
  var bundleID: String
  var name: String
}

@MainActor @Observable
final class FrontAppProvider {
  private(set) var app: FrontApp? = nil
  private(set) var icon: NSImage? = nil
  @ObservationIgnored private var token: NSObjectProtocol? = nil

  init() {
    update(NSWorkspace.shared.frontmostApplication)
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      Task { @MainActor [weak self] in self?.update(app) }
    }
  }

  private func update(_ running: NSRunningApplication?) {
    guard let running, running.bundleIdentifier != Bundle.main.bundleIdentifier,
          running.activationPolicy == .regular else { return }
    app = FrontApp(bundleID: running.bundleIdentifier ?? "", name: running.localizedName ?? "")
    icon = running.icon
  }
}
