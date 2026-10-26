import AppKit
import Observation
import os

/// The unlock chord: a virtual key code plus device-independent modifier flags.
struct KeyChord: Codable, Hashable, Sendable {
  var keyCode: Int = 37                        // L
  var modifiers: UInt = NSEvent.ModifierFlags([.control, .option, .command]).rawValue
  var label: String = "L"                      // key cap as typed, for display

  var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection([.control, .option, .shift, .command]) }
  var cgFlags: CGEventFlags {
    var f: CGEventFlags = []
    let m = flags
    if m.contains(.control) { f.insert(.maskControl) }
    if m.contains(.option) { f.insert(.maskAlternate) }
    if m.contains(.shift) { f.insert(.maskShift) }
    if m.contains(.command) { f.insert(.maskCommand) }
    return f
  }
  var display: String {
    let m = flags
    var s = ""
    if m.contains(.control) { s += "⌃" }
    if m.contains(.option) { s += "⌥" }
    if m.contains(.shift) { s += "⇧" }
    if m.contains(.command) { s += "⌘" }
    return s + label.uppercased()
  }
}

/// Blocks every keyboard, mouse, trackpad and scroll event from every device (built-in or external)
/// with a session-wide HID event tap, while the screen stays visible. Only the unlock chord
/// passes, and it releases the lock. Needs the Accessibility permission.
@MainActor @Observable
final class InputLockProvider {
  private(set) var locked = false
  private(set) var lastError: String? = nil
  var chord = KeyChord() { didSet { chordKey = Int64(chord.keyCode); chordFlags = chord.cgFlags.rawValue } }
  @ObservationIgnored nonisolated(unsafe) private var chordKey: Int64 = 37
  @ObservationIgnored nonisolated(unsafe) private var chordFlags: UInt64 = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
  @ObservationIgnored nonisolated(unsafe) private var tap: CFMachPort? = nil
  @ObservationIgnored private var source: CFRunLoopSource? = nil
  private let log = Logger(subsystem: "dev.barrly", category: "inputlock")

  var authorized: Bool { AXIsProcessTrusted() }

  func requestAuthorization() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
  }

  func toggle() { locked ? unlock() : lock() }

  func lock() {
    guard !locked else { return }
    guard authorized else { requestAuthorization(); lastError = "Accessibility permission is required."; return }
    let info = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask.max, callback: InputLockProvider.callback, userInfo: info) else {
      lastError = "Could not install the input filter. Check Accessibility permission."
      log.error("tap create failed"); return
    }
    self.tap = tap
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    CGEvent.tapEnable(tap: tap, enable: true)
    lastError = nil
    locked = true
    log.info("input locked")
  }

  func unlock() {
    guard locked else { return }
    if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil; source = nil
    locked = false
    log.info("input unlocked")
  }

  // Runs on the main thread (the tap's run loop source lives on the main run loop). Everything it
  // touches is marked nonisolated(unsafe) and only ever written from the main actor.
  private static let callback: CGEventTapCallBack = { _, type, event, info in
    guard let info else { return Unmanaged.passUnretained(event) }
    let me = Unmanaged<InputLockProvider>.fromOpaque(info).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // The system switches a slow tap off; switch it straight back on so the lock holds.
      if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .keyDown:
      let code = event.getIntegerValueField(.keyboardEventKeycode)
      let flags = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).rawValue
      if code == me.chordKey && flags == me.chordFlags { Task { @MainActor in me.unlock() } }
    default: break
    }
    return nil
  }
}
