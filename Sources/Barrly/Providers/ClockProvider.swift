import Foundation
import Observation

@MainActor @Observable
final class ClockProvider {
  private(set) var now: Date = Date()
  @ObservationIgnored private var token: Scheduler.Token? = nil
  @ObservationIgnored private let scheduler: Scheduler
  @ObservationIgnored private var perSecond = false

  init(scheduler: Scheduler) { self.scheduler = scheduler; start() }

  /// Widgets whose format shows seconds call this; it only ever escalates to 1 s ticks.
  func requireSeconds() { if !perSecond { perSecond = true; start() } }

  private func start() {
    scheduler.cancel(token)
    token = scheduler.schedule(every: perSecond ? 1 : 60, aligned: true) { [weak self] in self?.now = Date() }
  }
}
