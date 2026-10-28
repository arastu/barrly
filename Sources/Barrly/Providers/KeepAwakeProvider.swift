import Foundation
import IOKit.pwr_mgt
import Observation
import os

/// Keeps the Mac and its display awake, like a caffeinate / Amphetamine toggle. Two callers share
/// it: the user (the widget, a URL) and the input lock, which borrows it while locked so the
/// screen stays on even when the user has not switched it on. `active` is true while either holds.
@MainActor @Observable
final class KeepAwakeProvider {
  /// Switched on by the user (widget click, barrly://awake). Survives a lock/unlock cycle.
  private(set) var manual = false
  /// Held by the input lock while it is engaged with "keep awake while locked" on.
  private(set) var lockHeld = false
  var active: Bool { manual || lockHeld }

  @ObservationIgnored private var assertion: IOPMAssertionID = 0
  @ObservationIgnored private var activityAssertion: IOPMAssertionID = 0
  @ObservationIgnored private var activityTimer: Timer? = nil
  private let log = Logger(subsystem: "dev.barrly", category: "keepawake")

  func toggle() { setManual(!manual) }
  func setManual(_ on: Bool) { guard manual != on else { return }; manual = on; sync() }
  func setLockHeld(_ on: Bool) { guard lockHeld != on else { return }; lockHeld = on; sync() }

  private func sync() { active ? hold() : release() }

  // Two mechanisms: the assertion stops idle display/system sleep, and a periodic "user is active"
  // declaration resets the idle timer so the screen saver, dimming and the lock screen stay away
  // too (while input is locked the blocked HID events no longer count as activity).
  private func hold() {
    guard assertion == 0 else { return }
    let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Barrly keep awake" as CFString, &assertion)
    if r != kIOReturnSuccess { assertion = 0; log.error("power assertion failed: \(r)") }
    declareActivity()
    activityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.declareActivity() }
    }
    log.info("keep awake on")
  }

  private func declareActivity() {
    IOPMAssertionDeclareUserActivity("Barrly keep awake" as CFString, kIOPMUserActiveLocal, &activityAssertion)
  }

  private func release() {
    activityTimer?.invalidate(); activityTimer = nil
    if activityAssertion != 0 { IOPMAssertionRelease(activityAssertion); activityAssertion = 0 }
    guard assertion != 0 else { return }
    IOPMAssertionRelease(assertion); assertion = 0
    log.info("keep awake off")
  }
}
