import Foundation
import Testing
@testable import Barrly

@Suite struct JalaliTests {
  @Test func knownDates() {
    #expect(JalaliDate(gregorianYear: 2024, month: 10, day: 20) == JalaliDate(year: 1403, month: 7, day: 29))
    #expect(JalaliDate(gregorianYear: 2026, month: 10, day: 25) == JalaliDate(year: 1405, month: 8, day: 3))
    #expect(JalaliDate(gregorianYear: 2025, month: 3, day: 21) == JalaliDate(year: 1404, month: 1, day: 1))
    #expect(JalaliDate(gregorianYear: 2024, month: 3, day: 19) == JalaliDate(year: 1402, month: 12, day: 29))
  }

  @Test func matchesFoundationPersianCalendar() {
    var persian = Calendar(identifier: .persian); persian.timeZone = TimeZone(identifier: "UTC")!
    var greg = Calendar(identifier: .gregorian); greg.timeZone = TimeZone(identifier: "UTC")!
    var date = greg.date(from: DateComponents(year: 1970, month: 1, day: 1))!
    let end = greg.date(from: DateComponents(year: 2100, month: 12, day: 31))!
    var mismatches = 0
    while date <= end {
      let g = greg.dateComponents([.year, .month, .day], from: date)
      let p = persian.dateComponents([.year, .month, .day], from: date)
      let j = JalaliDate(gregorianYear: g.year!, month: g.month!, day: g.day!)
      if j.year != p.year || j.month != p.month || j.day != p.day { mismatches += 1 }
      date = greg.date(byAdding: .day, value: 7, to: date)!
    }
    #expect(mismatches == 0)
  }

  @Test func formatting() {
    let j = JalaliDate(year: 1405, month: 8, day: 3)
    #expect(j.formatted("d MMMM", persianDigits: true) == "۳ آبان")
    #expect(j.formatted("yyyy/MM/dd", persianDigits: false) == "1405/08/03")
    #expect(j.formatted("EEEE d MMMM", persianDigits: false, weekday: 1) == "یکشنبه 3 آبان")
  }
}
