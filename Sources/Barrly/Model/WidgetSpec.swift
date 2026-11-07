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
  var includeBrowsers: Bool = false
  // cpu / ram
  var interval: Double = 5
  // wifi
  var wifiShow: WifiShow = .none   // icon only; a click copies the IP and shows it for a moment
  // battery
  var warnBelow: Int = 20
  var showPercent: Bool = true
  // volume
  var volumeStep: Int = 6
  // input lock
  var unlockChord: KeyChord = KeyChord()
  var lockChord: KeyChord? = KeyChord()
  var keepAwake: Bool = true   // hold a power assertion while locked so the Mac and display stay on
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
  // claude code
  var claudeSession: String = ""        // Rex session (label) new tabs open in; "" = one named Claude, created if needed
  var collapsedSections: [Int] = []     // collapsed sections of the widget's list panel (Claude Code groups, Rex states)
  var claudeHideWhenEmpty: Bool = false // hide the cup while there are no sessions
  // spacer
  var width: Double = 10
  // icon colour: "auto" (follow the global toggle + the widget's default), "none", or an AccentToken raw value
  var iconTint: String = "auto"

  enum WifiShow: String, Codable, CaseIterable, Sendable { case fullIP, none }

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
    includeBrowsers = try c.decodeIfPresent(Bool.self, forKey: .includeBrowsers) ?? d.includeBrowsers
    interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? d.interval
    // Decoded by raw value so a mode that no longer exists (the old "lastOctet") falls back instead of failing the load.
    wifiShow = (try c.decodeIfPresent(String.self, forKey: .wifiShow)).flatMap(WifiShow.init(rawValue:)) ?? d.wifiShow
    warnBelow = try c.decodeIfPresent(Int.self, forKey: .warnBelow) ?? d.warnBelow
    showPercent = try c.decodeIfPresent(Bool.self, forKey: .showPercent) ?? d.showPercent
    volumeStep = try c.decodeIfPresent(Int.self, forKey: .volumeStep) ?? d.volumeStep
    unlockChord = try c.decodeIfPresent(KeyChord.self, forKey: .unlockChord) ?? d.unlockChord
    lockChord = c.contains(.lockChord) ? try c.decodeIfPresent(KeyChord.self, forKey: .lockChord) : d.lockChord
    keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? d.keepAwake
    inputSourceMap = try c.decodeIfPresent([String: String].self, forKey: .inputSourceMap) ?? d.inputSourceMap
    clipChars = try c.decodeIfPresent(Int.self, forKey: .clipChars) ?? d.clipChars
    soonMinutes = try c.decodeIfPresent(Int.self, forKey: .soonMinutes) ?? d.soonMinutes
    claudeSession = try c.decodeIfPresent(String.self, forKey: .claudeSession) ?? d.claudeSession
    collapsedSections = try c.decodeIfPresent([Int].self, forKey: .collapsedSections) ?? d.collapsedSections
    claudeHideWhenEmpty = try c.decodeIfPresent(Bool.self, forKey: .claudeHideWhenEmpty) ?? d.claudeHideWhenEmpty
    width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
    iconTint = try c.decodeIfPresent(String.self, forKey: .iconTint) ?? d.iconTint
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
