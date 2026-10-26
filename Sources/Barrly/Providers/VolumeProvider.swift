import CoreAudio
import AudioToolbox
import Foundation
import Observation

struct VolumeState: Hashable, Sendable {
  var level: Double      // 0…1
  var muted: Bool
  var present: Bool      // an output device with a software volume exists
  var canMute: Bool
  var deviceName: String
}

/// Default output device volume / mute via CoreAudio, pushed by property listeners.
/// No polling: CoreAudio tells us when the level, the mute flag or the default device changes.
@MainActor @Observable
final class VolumeProvider {
  private(set) var state = VolumeState(level: 0, muted: false, present: false, canMute: false, deviceName: "")
  @ObservationIgnored private var device: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
  @ObservationIgnored private var volumeAddress: AudioObjectPropertyAddress? = nil
  @ObservationIgnored private var lastNonZero: Double = 0.5

  private static let defaultOutput = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  private static let mute = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
  private static let name = AudioObjectPropertyAddress(
    mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  /// Candidates for the device's output level, most preferred first.
  private static let volumeCandidates: [AudioObjectPropertyAddress] = [
    AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain),
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain),
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: 1),
  ]

  // C callback (CoreAudio thread) → main actor. Same pattern as BatteryProvider.
  private static let listener: AudioObjectPropertyListenerProc = { _, _, _, ctx in
    guard let ctx else { return noErr }
    let me = Unmanaged<VolumeProvider>.fromOpaque(ctx).takeUnretainedValue()
    Task { @MainActor in me.deviceChanged() }
    return noErr
  }

  init() {
    var addr = Self.defaultOutput
    AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &addr, Self.listener, Unmanaged.passUnretained(self).toOpaque())
    attachToDefaultDevice()
  }

  /// Called when anything we listen to changes; cheap enough to just re-resolve the device.
  private func deviceChanged() {
    let current = Self.read(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, as: AudioObjectID.self) ?? AudioObjectID(kAudioObjectUnknown)
    if current != device { attachToDefaultDevice() } else { refresh() }
  }

  private func attachToDefaultDevice() {
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    if device != kAudioObjectUnknown {
      if var a = volumeAddress { AudioObjectRemovePropertyListener(device, &a, Self.listener, ctx) }
      var m = Self.mute; AudioObjectRemovePropertyListener(device, &m, Self.listener, ctx)
    }
    device = Self.read(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, as: AudioObjectID.self) ?? AudioObjectID(kAudioObjectUnknown)
    volumeAddress = nil
    guard device != kAudioObjectUnknown else { state = VolumeState(level: 0, muted: false, present: false, canMute: false, deviceName: ""); return }
    for cand in Self.volumeCandidates {
      var a = cand
      if AudioObjectHasProperty(device, &a) { volumeAddress = cand; break }
    }
    if var a = volumeAddress { AudioObjectAddPropertyListener(device, &a, Self.listener, ctx) }
    var m = Self.mute
    if AudioObjectHasProperty(device, &m) { AudioObjectAddPropertyListener(device, &m, Self.listener, ctx) }
    refresh()
  }

  func refresh() {
    guard device != kAudioObjectUnknown, let volumeAddress else { state.present = false; return }
    let level = Double(Self.read(device, volumeAddress, as: Float32.self) ?? 0)
    var m = Self.mute
    let canMute = AudioObjectHasProperty(device, &m)
    let muted = canMute ? (Self.read(device, Self.mute, as: UInt32.self) ?? 0) != 0 : false
    let name = (Self.read(device, Self.name, as: CFString?.self) ?? nil).map { $0 as String } ?? ""
    if level > 0 { lastNonZero = level }
    state = VolumeState(level: min(1, max(0, level)), muted: muted, present: true, canMute: canMute, deviceName: name)
  }

  // MARK: control

  func set(level: Double) {
    guard device != kAudioObjectUnknown, let volumeAddress else { return }
    var v = Float32(min(1, max(0, level)))
    var a = volumeAddress
    AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    if state.muted && state.canMute && level > 0 { setMuted(false) }
    refresh()
  }

  func adjust(byPercent step: Int) {
    let next = (Double(Int((state.level * 100).rounded()) + step) / 100)
    set(level: next)
  }

  func toggleMute() {
    if state.canMute { setMuted(!state.muted) }
    else if state.level > 0 { lastNonZero = state.level; set(level: 0) }
    else { set(level: lastNonZero) }
  }

  private func setMuted(_ on: Bool) {
    var v: UInt32 = on ? 1 : 0
    var a = Self.mute
    AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    refresh()
  }

  // MARK: CoreAudio helpers

  private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as: T.Type) -> T? {
    var a = address
    guard AudioObjectHasProperty(object, &a) else { return nil }
    var size = UInt32(MemoryLayout<T>.size)
    let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { ptr.deallocate() }
    guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, ptr) == noErr else { return nil }
    return ptr.move()
  }
}
