import Foundation

enum Side: String, Codable, CaseIterable, Sendable, Identifiable {
  case left, center, right
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

/// Accent tokens (Catppuccin names) — resolved per appearance by the Theme.
enum AccentToken: String, Codable, CaseIterable, Sendable, Identifiable {
  case mauve, blue, lavender, sapphire, sky, teal, green, yellow, peach, maroon, red, pink, flamingo
  var id: String { rawValue }
}

/// A glass capsule holding an ordered list of widgets.
struct Surface: Codable, Hashable, Identifiable, Sendable {
  var id: UUID = UUID()
  var name: String
  var tint: AccentToken? = nil
  var widgets: [WidgetSpec]
}

struct Layout: Codable, Hashable, Sendable {
  var left: [Surface]
  var center: [Surface]
  var right: [Surface]

  subscript(side: Side) -> [Surface] {
    get { switch side { case .left: left; case .center: center; case .right: right } }
    set { switch side { case .left: left = newValue; case .center: center = newValue; case .right: right = newValue } }
  }
  var allSurfaces: [Surface] { left + center + right }
  var allWidgets: [WidgetSpec] { allSurfaces.flatMap(\.widgets) }
}

enum DisplaySelection: String, Codable, CaseIterable, Sendable { case all, main }
/// System Liquid Glass variants: clear (see-through, like the Dock and HUDs) or regular (frosted).
enum GlassStyle: String, Codable, CaseIterable, Sendable { case clear, regular }

struct AppearanceSettings: Codable, Hashable, Sendable {
  var barHeight: Double = 38
  var margin: Double = 6
  var yOffset: Double = 6
  var pillHeight: Double = 30
  var pillRadius: Double = 15
  var chipHeight: Double = 22
  var chipRadius: Double = 11
  var gap: Double = 8
  var accent: AccentToken = .mauve
  var alwaysOnTop: Bool = false
  var displays: DisplaySelection = .all
  var respectNotch: Bool = false
  var labelFontSize: Double = 13
  var iconFontSize: Double = 14
  var colorfulIcons: Bool = true
  var glassStyle: GlassStyle = .clear

  // Tolerant decoding so older saved settings pick up new fields with their defaults.
  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = AppearanceSettings()
    barHeight = try c.decodeIfPresent(Double.self, forKey: .barHeight) ?? d.barHeight
    margin = try c.decodeIfPresent(Double.self, forKey: .margin) ?? d.margin
    yOffset = try c.decodeIfPresent(Double.self, forKey: .yOffset) ?? d.yOffset
    pillHeight = try c.decodeIfPresent(Double.self, forKey: .pillHeight) ?? d.pillHeight
    pillRadius = try c.decodeIfPresent(Double.self, forKey: .pillRadius) ?? d.pillRadius
    chipHeight = try c.decodeIfPresent(Double.self, forKey: .chipHeight) ?? d.chipHeight
    chipRadius = try c.decodeIfPresent(Double.self, forKey: .chipRadius) ?? d.chipRadius
    gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? d.gap
    accent = try c.decodeIfPresent(AccentToken.self, forKey: .accent) ?? d.accent
    alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? d.alwaysOnTop
    displays = try c.decodeIfPresent(DisplaySelection.self, forKey: .displays) ?? d.displays
    respectNotch = try c.decodeIfPresent(Bool.self, forKey: .respectNotch) ?? d.respectNotch
    labelFontSize = try c.decodeIfPresent(Double.self, forKey: .labelFontSize) ?? d.labelFontSize
    iconFontSize = try c.decodeIfPresent(Double.self, forKey: .iconFontSize) ?? d.iconFontSize
    colorfulIcons = try c.decodeIfPresent(Bool.self, forKey: .colorfulIcons) ?? d.colorfulIcons
    glassStyle = try c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle) ?? d.glassStyle
  }
}

struct Settings: Codable, Hashable, Sendable {
  var version: Int = 5
  var layout: Layout
  var appearance: AppearanceSettings = AppearanceSettings()
  var launchAtLogin: Bool = false

  /// Brings older saved settings up to the current layout conventions.
  mutating func migrate() {
    if version < 2 {
      // v2: the meeting capsule lives on the left, right after Now playing.
      if let i = layout.right.firstIndex(where: { $0.widgets.contains { $0.kind == .meeting } }) {
        let m = layout.right.remove(at: i)
        let after = layout.left.firstIndex(where: { $0.widgets.contains { $0.kind == .nowPlaying } }).map { $0 + 1 } ?? layout.left.count
        layout.left.insert(m, at: after)
      }
      version = 2
    }
    if version < 3 {
      // v3: the volume widget joins the status capsule, right after Wi-Fi.
      if !layout.allWidgets.contains(where: { $0.kind == .volume }),
         let s = layout.right.firstIndex(where: { $0.widgets.contains { $0.kind == .wifi } }),
         let w = layout.right[s].widgets.firstIndex(where: { $0.kind == .wifi }) {
        layout.right[s].widgets.insert(WidgetSpec(.volume, hiddenInZen: true), at: w + 1)
      }
      version = 3
    }
    if version < 4 {
      // v4: the VPN indicator (auto-hiding) joins the status capsule, right after Wi-Fi.
      if !layout.allWidgets.contains(where: { $0.kind == .vpn }),
         let s = layout.right.firstIndex(where: { $0.widgets.contains { $0.kind == .wifi } }),
         let w = layout.right[s].widgets.firstIndex(where: { $0.kind == .wifi }) {
        layout.right[s].widgets.insert(WidgetSpec(.vpn), at: w + 1)
      }
      version = 4
    }
    if version < 5 {
      // v5: the input lock sits at the end of the status capsule.
      if !layout.allWidgets.contains(where: { $0.kind == .inputLock }), !layout.right.isEmpty {
        layout.right[layout.right.count - 1].widgets.append(WidgetSpec(.inputLock))
      }
      version = 5
    }
  }

  /// Reproduces the user's sketchybar bar exactly.
  static var `default`: Settings {
    Settings(layout: Layout(
      left: [
        Surface(name: "Navigation", widgets: [
          WidgetSpec(.appleMenu),
          WidgetSpec(.workspaces, hoverable: false),
          WidgetSpec(.spacer, hoverable: false),
          WidgetSpec(.frontApp, hoverable: false),
        ]),
        Surface(name: "Now playing", widgets: [
          WidgetSpec(.nowPlaying, hiddenInZen: true),
        ]),
        Surface(name: "Meeting", tint: .lavender, widgets: [
          WidgetSpec(.meeting),
        ]),
      ],
      center: [],
      right: [
        Surface(name: "Status", widgets: [
          WidgetSpec(.cpu, hiddenInZen: true, secondary: true),
          WidgetSpec(.ram, hiddenInZen: true, secondary: true),
          WidgetSpec(.wifi, hiddenInZen: true),
          WidgetSpec(.vpn),
          WidgetSpec(.volume, hiddenInZen: true),
          WidgetSpec(.battery, hoverable: false),
          WidgetSpec(.spacer, hoverable: false),
          WidgetSpec(.jalaliDate, hiddenInZen: true, secondary: true) { $0.clickApp = "Roozegar" },
          WidgetSpec(.clock) { $0.clickApp = "Calendar" },
          WidgetSpec(.spacer, hoverable: false),
          WidgetSpec(.inputSource, hiddenInZen: true, hoverable: false),
          WidgetSpec(.inputLock),
        ]),
      ]
    ))
  }
}
