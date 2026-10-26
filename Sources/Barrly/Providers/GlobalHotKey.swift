import AppKit
import Carbon.HIToolbox

/// A system-wide hot key (Carbon RegisterEventHotKey: no Accessibility permission needed).
@MainActor
final class GlobalHotKey {
  private var ref: EventHotKeyRef? = nil
  private let id: UInt32
  nonisolated(unsafe) private let handler: () -> Void
  private static var next: UInt32 = 1
  nonisolated(unsafe) private static var registry: [UInt32: GlobalHotKey] = [:]
  private static var installed = false

  init?(chord: KeyChord, handler: @escaping () -> Void) {
    self.handler = handler
    id = Self.next; Self.next += 1
    Self.installHandlerOnce()
    var mods: UInt32 = 0
    let f = chord.flags
    if f.contains(.control) { mods |= UInt32(controlKey) }
    if f.contains(.option) { mods |= UInt32(optionKey) }
    if f.contains(.shift) { mods |= UInt32(shiftKey) }
    if f.contains(.command) { mods |= UInt32(cmdKey) }
    let hk = EventHotKeyID(signature: OSType(0x4252_4C59) /* BRLY */, id: id)
    var r: EventHotKeyRef? = nil
    guard RegisterEventHotKey(UInt32(chord.keyCode), mods, hk, GetApplicationEventTarget(), 0, &r) == noErr, let r else { return nil }
    ref = r
    Self.registry[id] = self
  }

  func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    ref = nil
    Self.registry[id] = nil
  }

  private static func installHandlerOnce() {
    guard !installed else { return }
    installed = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var hk = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &hk)
      if let key = GlobalHotKey.registry[hk.id] { key.handler() }
      return noErr
    }, 1, &spec, nil, nil)
  }
}
