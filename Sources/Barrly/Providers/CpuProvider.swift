import Darwin
import Foundation
import Observation

/// CPU load across all cores, from host_processor_info tick deltas.
@MainActor @Observable
final class CpuProvider {
  private(set) var usage: Double = 0   // 0...1
  @ObservationIgnored private var previous: [UInt32] = []
  @ObservationIgnored private var token: Scheduler.Token? = nil
  @ObservationIgnored private let scheduler: Scheduler

  init(scheduler: Scheduler, interval: TimeInterval = 5) {
    self.scheduler = scheduler
    token = scheduler.schedule(every: interval) { [weak self] in self?.sample() }
  }
  func setInterval(_ s: TimeInterval) { if let token { scheduler.setInterval(token, s) } }

  private func sample() {
    var cpuCount: natural_t = 0
    var info: processor_info_array_t? = nil
    var count: mach_msg_type_number_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &count) == KERN_SUCCESS, let info else { return }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
    let states = Int(CPU_STATE_MAX)
    var ticks: [UInt32] = []
    ticks.reserveCapacity(Int(cpuCount) * states)
    for i in 0..<(Int(cpuCount) * states) { ticks.append(UInt32(bitPattern: info[i])) }
    if previous.count == ticks.count {
      var busy: Double = 0, total: Double = 0
      for c in 0..<Int(cpuCount) {
        let b = c * states
        let user = Double(ticks[b + Int(CPU_STATE_USER)] &- previous[b + Int(CPU_STATE_USER)])
        let sys = Double(ticks[b + Int(CPU_STATE_SYSTEM)] &- previous[b + Int(CPU_STATE_SYSTEM)])
        let nice = Double(ticks[b + Int(CPU_STATE_NICE)] &- previous[b + Int(CPU_STATE_NICE)])
        let idle = Double(ticks[b + Int(CPU_STATE_IDLE)] &- previous[b + Int(CPU_STATE_IDLE)])
        busy += user + sys + nice; total += user + sys + nice + idle
      }
      if total > 0 { usage = min(1, max(0, busy / total)) }
    }
    previous = ticks
  }
}
