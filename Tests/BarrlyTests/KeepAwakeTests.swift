import Foundation
import Testing
@testable import Barrly

@Suite struct KeepAwakeTests {
  @MainActor @Test func manualToggle() {
    let awake = KeepAwakeProvider()
    #expect(!awake.active)
    awake.toggle()
    #expect(awake.active && awake.manual)
    awake.toggle()
    #expect(!awake.active)
  }

  @MainActor @Test func lockHoldsAndReleasesWithoutTouchingManual() {
    let awake = KeepAwakeProvider()
    awake.setLockHeld(true)
    #expect(awake.active && !awake.manual && awake.lockHeld)
    awake.setLockHeld(false)
    #expect(!awake.active)
  }

  @MainActor @Test func manualKeepAwakeSurvivesLockCycle() {
    let awake = KeepAwakeProvider()
    awake.setManual(true)
    awake.setLockHeld(true)
    awake.setLockHeld(false)
    #expect(awake.active && awake.manual)
  }

  @MainActor @Test func lockOptionOffLeavesKeepAwakeAlone() {
    let awake = KeepAwakeProvider()
    let lock = InputLockProvider(awake: awake, defaults: UserDefaults(suiteName: "dev.barrly.tests.keepawake.\(UUID())")!)
    lock.keepAwake = false
    #expect(!awake.active)
    lock.keepAwake = true   // not locked, so still nothing held
    #expect(!awake.lockHeld)
  }
}
