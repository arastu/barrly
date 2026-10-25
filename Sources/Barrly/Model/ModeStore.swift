import Foundation
import Observation

/// Bar modes. Zen hides the "noisy" widgets (those flagged hiddenInZen). Persists across relaunch.
@MainActor @Observable
final class ModeStore {
  private static let zenKey = "mode.zen"
  var zen: Bool { didSet { UserDefaults.standard.set(zen, forKey: Self.zenKey) } }
  init() { zen = UserDefaults.standard.bool(forKey: Self.zenKey) }
  func toggleZen() { zen.toggle() }
}
