import AppKit
import Foundation

/// One timer for every polling job. Jobs register an interval; the scheduler coalesces wakeups,
/// aligns minute jobs to the wall clock, suspends while the machine sleeps and fires everything
/// once on wake (that wake burst is how "system_woke" is modelled).
@MainActor
final class Scheduler {
  final class Token { fileprivate let id = UUID(); fileprivate init() {} }

  private struct Job { let id: UUID; var interval: TimeInterval; var aligned: Bool; var next: Date; let run: @MainActor () -> Void }

  private var jobs: [UUID: Job] = [:]
  private var timer: DispatchSourceTimer? = nil
  private var suspended = false
  private var tokens: [NSObjectProtocol] = []
  private(set) var wakeups = 0
  private(set) var lastWake: Date? = nil

  init() {
    let nc = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
      tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor [weak self] in self?.suspend() } })
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor [weak self] in self?.resumeAndFireAll() } })
    }
  }

  /// Register a job. `aligned` snaps the next fire to a multiple of `interval` on the wall clock (e.g. minute boundaries).
  @discardableResult
  func schedule(every interval: TimeInterval, aligned: Bool = false, fireNow: Bool = true, _ run: @escaping @MainActor () -> Void) -> Token {
    let t = Token()
    jobs[t.id] = Job(id: t.id, interval: interval, aligned: aligned, next: Self.nextFire(after: Date(), interval: interval, aligned: aligned), run: run)
    if fireNow { run() }
    reschedule()
    return t
  }

  func cancel(_ token: Token?) {
    guard let token else { return }
    jobs[token.id] = nil; reschedule()
  }

  func setInterval(_ token: Token, _ interval: TimeInterval) {
    guard var j = jobs[token.id] else { return }
    j.interval = interval; j.next = Self.nextFire(after: Date(), interval: interval, aligned: j.aligned); jobs[token.id] = j; reschedule()
  }

  /// Run every job now (used by "refresh all").
  func fireAll() {
    let now = Date()
    for (id, var j) in jobs { j.next = Self.nextFire(after: now, interval: j.interval, aligned: j.aligned); jobs[id] = j }
    let all = Array(jobs.values)
    for j in all { j.run() }
    reschedule()
  }

  private static func nextFire(after now: Date, interval: TimeInterval, aligned: Bool) -> Date {
    guard aligned, interval >= 1 else { return now.addingTimeInterval(interval) }
    let t = now.timeIntervalSince1970
    return Date(timeIntervalSince1970: (floor(t / interval) + 1) * interval)
  }

  private func reschedule() {
    timer?.cancel(); timer = nil
    guard !suspended, let soonest = jobs.values.map(\.next).min() else { return }
    let delay = max(0, soonest.timeIntervalSinceNow)
    let leeway = min(1.0, max(0.05, delay * 0.1))
    let t = DispatchSource.makeTimerSource(queue: .main)
    t.schedule(deadline: .now() + delay, leeway: .milliseconds(Int(leeway * 1000)))
    t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.fireDue() } }
    t.resume(); timer = t
  }

  private func fireDue() {
    wakeups += 1
    let now = Date().addingTimeInterval(0.05)
    var due: [Job] = []
    for (id, var j) in jobs where j.next <= now {
      j.next = Self.nextFire(after: Date(), interval: j.interval, aligned: j.aligned); jobs[id] = j; due.append(j)
    }
    for j in due { j.run() }
    reschedule()
  }

  private func suspend() { suspended = true; timer?.cancel(); timer = nil }
  private func resumeAndFireAll() { suspended = false; lastWake = Date(); fireAll() }
}
