import Foundation
import Testing
@testable import Barrly

@Suite struct InputLockTests {
  private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "dev.barrly.tests.inputlock.\(UUID())")! }

  @MainActor @Test func firstUseAsksAndDeclineKeepsLockOff() {
    let lock = InputLockProvider(defaults: freshDefaults())
    var shown: [KeyChord] = []
    lock.presentIntro = { chord, keepAwake in shown.append(chord); #expect(keepAwake); return false }
    lock.lock()
    #expect(shown == [KeyChord()])
    #expect(!lock.locked)
    #expect(!lock.acknowledged)
    lock.lock()
    #expect(shown.count == 2) // keeps asking until approved
  }

  @MainActor @Test func acknowledgementPersistsAndResets() {
    let defaults = freshDefaults()
    defaults.set(true, forKey: InputLockProvider.acknowledgedKey)
    let lock = InputLockProvider(defaults: defaults)
    #expect(lock.acknowledged)
    lock.resetAcknowledgement()
    #expect(!lock.acknowledged)
    #expect(!defaults.bool(forKey: InputLockProvider.acknowledgedKey))
  }
}
