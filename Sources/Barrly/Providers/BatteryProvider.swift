import Foundation
import IOKit.ps
import Observation

struct BatteryState: Hashable, Sendable {
  var percent: Int
  var isCharging: Bool
  var isPluggedIn: Bool
  var present: Bool
}

/// IOPowerSources with push notifications; a 60 s poll is only a safety net.
@MainActor @Observable
final class BatteryProvider {
  private(set) var state = BatteryState(percent: 100, isCharging: false, isPluggedIn: true, present: false)
  @ObservationIgnored private var source: CFRunLoopSource? = nil
  @ObservationIgnored private var token: Scheduler.Token? = nil

  init(scheduler: Scheduler) {
    token = scheduler.schedule(every: 60) { [weak self] in self?.refresh() }
    let ctx = Unmanaged.passUnretained(self).toOpaque()
    source = IOPSNotificationCreateRunLoopSource({ ctx in
      guard let ctx else { return }
      let me = Unmanaged<BatteryProvider>.fromOpaque(ctx).takeUnretainedValue()
      Task { @MainActor in me.refresh() }
    }, ctx)?.takeRetainedValue()
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
  }


  func refresh() {
    guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
    for ps in list {
      guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
            d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
      let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
      let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
      let charging = d[kIOPSIsChargingKey] as? Bool ?? false
      let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
      let pct = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
      state = BatteryState(percent: pct, isCharging: charging, isPluggedIn: ac, present: true)
      return
    }
    state.present = false
  }
}
