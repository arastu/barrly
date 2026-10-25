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
}

struct Settings: Codable, Hashable, Sendable {
  var version: Int = 2
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
          WidgetSpec(.battery, hoverable: false),
          WidgetSpec(.spacer, hoverable: false),
          WidgetSpec(.jalaliDate, hiddenInZen: true, secondary: true) { $0.clickApp = "Roozegar" },
          WidgetSpec(.clock) { $0.clickApp = "Calendar" },
          WidgetSpec(.spacer, hoverable: false),
          WidgetSpec(.inputSource, hiddenInZen: true, hoverable: false),
        ]),
      ]
    ))
  }
}
