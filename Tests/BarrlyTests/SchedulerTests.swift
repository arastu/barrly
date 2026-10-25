import Foundation
import Testing
@testable import Barrly

@Suite struct SchedulerTests {
  @Test @MainActor func firesNowAndCoalesces() async throws {
    let s = Scheduler()
    var a = 0, b = 0
    s.schedule(every: 0.2) { a += 1 }
    s.schedule(every: 0.2) { b += 1 }
    #expect(a == 1 && b == 1)
    try await Task.sleep(for: .milliseconds(550))
    #expect(a >= 2 && b >= 2)
    #expect(s.wakeups <= 3) // both jobs share wakeups
  }

  @Test @MainActor func fireAllRunsEveryJob() {
    let s = Scheduler()
    var n = 0
    s.schedule(every: 3600, fireNow: false) { n += 1 }
    s.schedule(every: 3600, fireNow: false) { n += 1 }
    s.fireAll()
    #expect(n == 2)
  }
}
