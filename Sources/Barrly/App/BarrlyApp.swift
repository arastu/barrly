import SwiftUI

@main
struct BarrlyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    SwiftUI.Settings {
      SettingsView().environment(delegate.runtime)
    }
  }
}
