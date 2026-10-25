import EventKit
import Foundation
import Observation
import os

struct Meeting: Hashable, Sendable {
  enum Phase: Hashable, Sendable { case inProgress, soon, later }
  var title: String
  var start: Date
  var end: Date
  var url: URL?
  var phase: Phase
}

/// Current or next meeting today from EventKit. Refreshes on store changes, every minute, and on wake.
@MainActor @Observable
final class CalendarProvider {
  private(set) var meeting: Meeting? = nil
  private(set) var authorized = false
  var soonMinutes: Int = 10 { didSet { if soonMinutes != oldValue { refresh() } } }

  @ObservationIgnored private let store = EKEventStore()
  @ObservationIgnored private let log = Logger(subsystem: "dev.barrly", category: "calendar")
  @ObservationIgnored private var token: NSObjectProtocol? = nil
  @ObservationIgnored private var tick: Scheduler.Token? = nil

  init(scheduler: Scheduler) {
    tick = scheduler.schedule(every: 60, aligned: true, fireNow: false) { [weak self] in self?.refresh() }
    token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
      Task { @MainActor [weak self] in self?.refresh() }
    }
    Task { await requestAccess() }
  }

  private func requestAccess() async {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess: authorized = true
    case .notDetermined, .writeOnly:
      authorized = (try? await store.requestFullAccessToEvents()) ?? false
    default: authorized = false
    }
    if authorized { refresh() } else { log.warning("calendar access not granted") }
  }

  func refresh() {
    guard authorized else { return }
    let now = Date()
    let cal = Calendar.current
    let start = cal.startOfDay(for: now)
    let end = cal.date(byAdding: .day, value: 1, to: start)!
    let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
      .filter { !$0.isAllDay && $0.status != .canceled }
    var current: EKEvent? = nil, next: EKEvent? = nil
    for e in events {
      if e.startDate <= now && now < e.endDate { if current == nil || e.endDate < current!.endDate { current = e } }
      else if e.startDate > now { if next == nil || e.startDate < next!.startDate { next = e } }
    }
    let m: Meeting?
    if let e = current {
      m = Meeting(title: e.title ?? "", start: e.startDate, end: e.endDate, url: Self.url(of: e), phase: .inProgress)
    } else if let e = next {
      let soon = e.startDate.timeIntervalSince(now) <= Double(soonMinutes) * 60
      m = Meeting(title: e.title ?? "", start: e.startDate, end: e.endDate, url: Self.url(of: e), phase: soon ? .soon : .later)
    } else { m = nil }
    if m != meeting { meeting = m }
  }

  private static func url(of e: EKEvent) -> URL? {
    MeetingURLExtractor.extract(from: [e.url?.absoluteString, e.notes, e.location])
  }
}
