import AppKit
import Observation

/// Mirrors system appearance + accessibility switches, live.
@MainActor @Observable
final class AppearanceModel {
  private(set) var isDark: Bool = false
  private(set) var reduceTransparency: Bool = false
  private(set) var increaseContrast: Bool = false
  private(set) var reduceMotion: Bool = false

  @ObservationIgnored private var kvo: NSKeyValueObservation? = nil
  @ObservationIgnored private var token: NSObjectProtocol? = nil

  init() {
    refresh()
    kvo = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
      Task { @MainActor [weak self] in self?.refresh() }
    }
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
    ) { _ in Task { @MainActor [weak self] in self?.refresh() } }
  }

  func refresh() {
    isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let ws = NSWorkspace.shared
    reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
    increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
    reduceMotion = ws.accessibilityDisplayShouldReduceMotion
  }
}
