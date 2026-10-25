import Foundation

/// Per-widget user options. One flat struct keeps Settings UI and Codable trivial;
/// each widget reads only the fields it cares about.
struct WidgetOptions: Codable, Hashable, Sendable {
  // clock / jalali
  var clockFormat: String = "EEE d MMM  HH:mm"
  var persianDigits: Bool = true
  var jalaliFormat: String = "d MMMM"
  var clickApp: String? = nil
  // workspaces
  var maxIcons: Int = 4
  var hideEmpty: Bool = true
  var showIds: Bool = true
  // front app
  var showIcon: Bool = true
  var showName: Bool = true
  // now playing
  var nowPlayingFormat: String = "{title} – {artist}"
  var maxChars: Int = 48
  // cpu / ram
  var interval: Double = 5
  // wifi
  var wifiShow: WifiShow = .lastOctet
  // battery
  var warnBelow: Int = 20
  var showPercent: Bool = true
  // input source
  var inputSourceMap: [String: String] = [
    "com.apple.keylayout.ABC": "EN",
    "com.apple.keylayout.US": "EN",
    "com.apple.keylayout.Persian-ISIRI2901": "FA",
    "com.apple.keylayout.Persian": "FA",
    "com.apple.keylayout.Persian-Standard": "FA",
  ]
  // meeting
  var clipChars: Int = 16
  var soonMinutes: Int = 10
  // spacer
  var width: Double = 10

  enum WifiShow: String, Codable, CaseIterable, Sendable { case lastOctet, fullIP, none }

  // Tolerant decoding: missing keys fall back to defaults so old settings keep loading.
  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = WidgetOptions()
    clockFormat = try c.decodeIfPresent(String.self, forKey: .clockFormat) ?? d.clockFormat
    persianDigits = try c.decodeIfPresent(Bool.self, forKey: .persianDigits) ?? d.persianDigits
    jalaliFormat = try c.decodeIfPresent(String.self, forKey: .jalaliFormat) ?? d.jalaliFormat
    clickApp = try c.decodeIfPresent(String.self, forKey: .clickApp)
    maxIcons = try c.decodeIfPresent(Int.self, forKey: .maxIcons) ?? d.maxIcons
    hideEmpty = try c.decodeIfPresent(Bool.self, forKey: .hideEmpty) ?? d.hideEmpty
    showIds = try c.decodeIfPresent(Bool.self, forKey: .showIds) ?? d.showIds
    showIcon = try c.decodeIfPresent(Bool.self, forKey: .showIcon) ?? d.showIcon
    showName = try c.decodeIfPresent(Bool.self, forKey: .showName) ?? d.showName
    nowPlayingFormat = try c.decodeIfPresent(String.self, forKey: .nowPlayingFormat) ?? d.nowPlayingFormat
    maxChars = try c.decodeIfPresent(Int.self, forKey: .maxChars) ?? d.maxChars
    interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? d.interval
    wifiShow = try c.decodeIfPresent(WifiShow.self, forKey: .wifiShow) ?? d.wifiShow
    warnBelow = try c.decodeIfPresent(Int.self, forKey: .warnBelow) ?? d.warnBelow
    showPercent = try c.decodeIfPresent(Bool.self, forKey: .showPercent) ?? d.showPercent
    inputSourceMap = try c.decodeIfPresent([String: String].self, forKey: .inputSourceMap) ?? d.inputSourceMap
    clipChars = try c.decodeIfPresent(Int.self, forKey: .clipChars) ?? d.clipChars
    soonMinutes = try c.decodeIfPresent(Int.self, forKey: .soonMinutes) ?? d.soonMinutes
    width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
  }
}

/// One placed widget inside a surface.
struct WidgetSpec: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var kind: WidgetKind
  var enabled: Bool = true
  var hiddenInZen: Bool = false
  var hoverable: Bool = true
  var secondary: Bool = false
  var options: WidgetOptions = WidgetOptions()

  init(_ kind: WidgetKind, enabled: Bool = true, hiddenInZen: Bool = false, hoverable: Bool = true,
       secondary: Bool = false, options: (inout WidgetOptions) -> Void = { _ in }) {
    self.kind = kind; self.enabled = enabled; self.hiddenInZen = hiddenInZen
    self.hoverable = hoverable; self.secondary = secondary
    var o = WidgetOptions(); options(&o); self.options = o
  }
}
