import Darwin
import Foundation
import Observation

/// Memory in use as a fraction of physical memory (active + wired + compressed), via host_statistics64.
@MainActor @Observable
final class MemoryProvider {
  private(set) var usedFraction: Double = 0
  private(set) var usedBytes: UInt64 = 0
  let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
  @ObservationIgnored private var token: Scheduler.Token? = nil
  @ObservationIgnored private let scheduler: Scheduler

  init(scheduler: Scheduler, interval: TimeInterval = 5) {
    self.scheduler = scheduler
    token = scheduler.schedule(every: interval) { [weak self] in self?.sample() }
  }
  func setInterval(_ s: TimeInterval) { if let token { scheduler.setInterval(token, s) } }

  private func sample() {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    guard kr == KERN_SUCCESS else { return }
    var pageSize: vm_size_t = 0
    host_page_size(mach_host_self(), &pageSize)
    let page = UInt64(pageSize)
    let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    usedBytes = used
    usedFraction = totalBytes > 0 ? min(1, Double(used) / Double(totalBytes)) : 0
  }
}
