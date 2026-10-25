import Foundation

/// Gregorian → Jalali (Shamsi) conversion, pure, no Foundation calendar needed.
/// Algorithm: the classic jdf arithmetic (same as the user's awk version).
struct JalaliDate: Hashable, Sendable {
  var year: Int, month: Int, day: Int

  static let monthNames = ["فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
                           "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"]
  static let weekdayNames = ["یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه", "شنبه"] // Sunday-first

  var monthName: String { Self.monthNames[month - 1] }

  init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

  init(gregorianYear gy: Int, month gm: Int, day gd: Int) {
    let gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    var gy = gy, jy: Int
    if gy > 1600 { jy = 979; gy -= 1600 } else { jy = 0; gy -= 621 }
    let gy2 = gm > 2 ? gy + 1 : gy
    var days = 365 * gy + (gy2 + 3) / 4 - (gy2 + 99) / 100 + (gy2 + 399) / 400 - 80 + gd + gdm[gm - 1]
    jy += 33 * (days / 12053); days %= 12053
    jy += 4 * (days / 1461); days %= 1461
    if days > 365 { jy += (days - 1) / 365; days = (days - 1) % 365 }
    let jm: Int, jd: Int
    if days < 186 { jm = 1 + days / 31; jd = 1 + days % 31 } else { jm = 7 + (days - 186) / 30; jd = 1 + (days - 186) % 30 }
    self.init(year: jy, month: jm, day: jd)
  }

  init(_ date: Date, calendar: Calendar = .current) {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(gregorianYear: c.year!, month: c.month!, day: c.day!)
  }

  /// Formats with a tiny subset of DateFormatter patterns: d, dd, M, MM, MMMM, yyyy, yy, EEEE.
  func formatted(_ pattern: String, persianDigits: Bool, weekday: Int? = nil) -> String {
    var out = "", i = pattern.startIndex
    while i < pattern.endIndex {
      let ch = pattern[i]
      var run = 0; var j = i
      while j < pattern.endIndex, pattern[j] == ch { run += 1; j = pattern.index(after: j) }
      switch ch {
      case "d": out += run >= 2 ? String(format: "%02d", day) : "\(day)"
      case "M": out += run >= 4 ? monthName : run >= 2 ? String(format: "%02d", month) : "\(month)"
      case "y": out += run <= 2 ? String(format: "%02d", year % 100) : "\(year)"
      case "E": if let weekday { out += Self.weekdayNames[(weekday - 1) % 7] }
      default: out += String(repeating: ch, count: run)
      }
      i = j
    }
    return persianDigits ? Self.persianDigits(out) : out
  }

  static func persianDigits(_ s: String) -> String {
    let digits: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
    return String(s.map { c in
      if let v = c.wholeNumberValue, c.isASCII { return digits[v] }
      return c
    })
  }
}
