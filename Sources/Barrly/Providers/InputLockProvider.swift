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
  /// Global shortcut that engages the lock (nil = none). While locked the event tap sees the keys
  /// first, so the same chord as `chord` makes it a toggle.
  var lockChord: KeyChord? = nil { didSet { if lockChord != oldValue { registerHotKey() } } }
  /// Set while Settings records a shortcut so the hot key does not swallow the key press.
  var hotKeySuspended = false { didSet { if hotKeySuspended != oldValue { registerHotKey() } } }
  /// Keep the Mac and its display awake while locked: the lock holds the shared keep-awake
  /// provider for as long as it is engaged and lets go on unlock (a manual keep-awake stays on).
  var keepAwake = true { didSet { if locked { awake.setLockHeld(keepAwake) } } }
  let awake: KeepAwakeProvider
  @ObservationIgnored private var hotKey: GlobalHotKey? = nil
  @ObservationIgnored nonisolated(unsafe) private var chordKey: Int64 = 37
  @ObservationIgnored nonisolated(unsafe) private var chordFlags: UInt64 = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
  @ObservationIgnored nonisolated(unsafe) private var tap: CFMachPort? = nil
  @ObservationIgnored private var source: CFRunLoopSource? = nil
  private let log = Logger(subsystem: "dev.barrly", category: "inputlock")

  static let acknowledgedKey = "inputLock.acknowledged"
  /// The user has read the first-use explanation and approved the lock. Until then every lock
  /// attempt (click, shortcut, URL) shows the explanation instead and only proceeds on approval.
  private(set) var acknowledged: Bool { didSet { defaults.set(acknowledged, forKey: Self.acknowledgedKey) } }
  /// Shows the first-use explanation for the given unlock chord and returns the user's decision.
  /// Replaceable so tests do not open a window.
  @ObservationIgnored var presentIntro: @MainActor (KeyChord, _ keepAwake: Bool) -> Bool = InputLockProvider.showIntroAlert
  @ObservationIgnored private var introShowing = false
  @ObservationIgnored private let defaults: UserDefaults

  init(awake: KeepAwakeProvider = KeepAwakeProvider(), defaults: UserDefaults = .standard) {
    self.awake = awake
    self.defaults = defaults
    acknowledged = defaults.bool(forKey: Self.acknowledgedKey)
  }

  /// Makes the next lock attempt show the first-use explanation again.
  func resetAcknowledgement() { acknowledged = false }

  var authorized: Bool { AXIsProcessTrusted() }

  func requestAuthorization() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
  }

  func toggle() { locked ? unlock() : lock() }

  private func registerHotKey() {
    hotKey?.unregister(); hotKey = nil
    guard let lockChord, !hotKeySuspended else { return }
    hotKey = GlobalHotKey(chord: lockChord) { [weak self] in
      Task { @MainActor in self?.lock() }
    }
    if hotKey == nil { lastError = "Could not register the lock shortcut \(lockChord.display); another app may own it." }
  }

  func lock() {
    guard !locked, !introShowing else { return }
    if !acknowledged {
      introShowing = true
      let approved = presentIntro(chord, keepAwake)
      introShowing = false
      guard approved else { log.info("lock declined at first use"); return }
      acknowledged = true
    }
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
    if keepAwake { awake.setLockHeld(true) }
    log.info("input locked")
  }

  func unlock() {
    guard locked else { return }
    if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil; source = nil
    locked = false
    awake.setLockHeld(false)
    log.info("input unlocked")
  }

  /// First-use explanation: what the lock does, how to get out, and what macOS will ask for.
  private static func showIntroAlert(chord: KeyChord, keepAwake: Bool) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Input lock")
    alert.messageText = "Lock all input?"
    alert.informativeText = """
      Barrly's input lock blocks every keyboard, mouse and trackpad, built-in and external, while the \
      screen stays on\(keepAwake ? " and the Mac is kept awake" : ""). Nothing you type or click gets \
      through until you press the unlock shortcut:

      \(chord.display)

      macOS asks for the Accessibility permission the first time; the lock cannot work without it. \
      If the shortcut ever fails to release the lock, hold the power button to shut the Mac down.

      Shortcuts can be changed in Barrly Settings › Widgets › Input lock. This notice is shown once.
      """
    alert.addButton(withTitle: "Lock input")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate()
    return alert.runModal() == .alertFirstButtonReturn
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
