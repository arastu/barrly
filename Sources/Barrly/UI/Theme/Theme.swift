import SwiftUI

/// Liquid Glass theme after Apple's HIG "Materials": glass is the functional layer only,
/// colour is used for state, text follows label / secondaryLabel / tertiaryLabel.
struct Palette: Sendable, Hashable {
  var glassTintAlpha: Double        // extra tint over the system glass (0 = pure system glass)
  var rim: Color                    // 1 px specular rim
  var highlight: Color              // raised lozenge (selection / hover)
  var highlightRim: Color
  var shadow: Color
  var popup: Color
  var text: Color
  var text2: Color
  var text3: Color
  var accents: [AccentToken: Color]
  func accent(_ t: AccentToken) -> Color { accents[t] ?? .accentColor }
}

extension Palette {
  // Catppuccin Latte / Macchiato, used only for state.
  static let light = Palette(
    glassTintAlpha: 0,
    rim: .white.opacity(0.55), highlight: .white.opacity(0.60), highlightRim: .white.opacity(0.90),
    shadow: .black.opacity(0.20), popup: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.90),
    text: Color(red: 0.106, green: 0.114, blue: 0.169).opacity(0.94),
    text2: Color(red: 0.106, green: 0.114, blue: 0.169).opacity(0.70),
    text3: Color(red: 0.106, green: 0.114, blue: 0.169).opacity(0.50),
    accents: [
      .mauve: Color(hex: 0x8839ef), .blue: Color(hex: 0x1e66f5), .lavender: Color(hex: 0x7287fd),
      .sapphire: Color(hex: 0x209fb5), .sky: Color(hex: 0x04a5e5), .teal: Color(hex: 0x179299),
      .green: Color(hex: 0x40a02b), .yellow: Color(hex: 0xdf8e1d), .peach: Color(hex: 0xfe640b),
      .maroon: Color(hex: 0xe64553), .red: Color(hex: 0xd20f39), .pink: Color(hex: 0xea76cb),
      .flamingo: Color(hex: 0xdd7878),
    ])
  static let dark = Palette(
    glassTintAlpha: 0,
    rim: .white.opacity(0.25), highlight: .white.opacity(0.30), highlightRim: .white.opacity(0.35),
    shadow: .black.opacity(0.50), popup: Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.90),
    text: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.95),
    text2: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.70),
    text3: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.50),
    accents: [
      .mauve: Color(hex: 0xc6a0f6), .blue: Color(hex: 0x8aadf4), .lavender: Color(hex: 0xb7bdf8),
      .sapphire: Color(hex: 0x7dc4e4), .sky: Color(hex: 0x91d7e3), .teal: Color(hex: 0x8bd5ca),
      .green: Color(hex: 0xa6da95), .yellow: Color(hex: 0xeed49f), .peach: Color(hex: 0xf5a97f),
      .maroon: Color(hex: 0xee99a0), .red: Color(hex: 0xed8796), .pink: Color(hex: 0xf5bde6),
      .flamingo: Color(hex: 0xf0c6c6),
    ])
}

struct Metrics: Sendable, Hashable {
  var barHeight: CGFloat
  var pillHeight: CGFloat
  var pillRadius: CGFloat
  var chipHeight: CGFloat
  var chipRadius: CGFloat
  var gap: CGFloat
  var cellPadding: CGFloat = 4      // horizontal padding inside a chip around icon+label
  var iconLabelSpacing: CGFloat = 5
  var surfacePadding: CGFloat = 4   // inset from the capsule edge to the first chip
}

struct Fonts: Sendable, Hashable {
  var labelSize: CGFloat
  var iconSize: CGFloat
  var label: Font { .system(size: labelSize, weight: .semibold) }
  var labelMedium: Font { .system(size: labelSize, weight: .medium) }
  var small: Font { .system(size: labelSize - 1, weight: .semibold) }
  var icon: Font { .system(size: iconSize, weight: .medium) }
  var iconLarge: Font { .system(size: iconSize + 1, weight: .medium) }
  var persian: Font {
    if NSFont(name: "Vazirmatn-SemiBold", size: labelSize) != nil { return .custom("Vazirmatn-SemiBold", size: labelSize) }
    return .system(size: labelSize, weight: .semibold)
  }
}

/// What views actually read. Re-resolved whenever appearance, accessibility or settings change.
struct ResolvedTheme: Sendable, Hashable {
  var palette: Palette
  var metrics: Metrics
  var fonts: Fonts
  var accent: Color
  var colorfulIcons: Bool
  var glassStyle: GlassStyle
  var widgetGlass: Bool
  var glassClearness: Double
  var isDark: Bool
  var reduceTransparency: Bool
  var increaseContrast: Bool
  var reduceMotion: Bool

  /// Accent used for text/icons that carry state. Light glass over bright wallpapers needs a
  /// deeper shade than the raw palette; Increase Contrast falls back to the label colour.
  func stateColor(_ token: AccentToken) -> Color {
    if increaseContrast { return palette.text }
    let c = palette.accent(token)
    return isDark ? c : c.mix(with: .black, by: 0.28)
  }

  /// Resting icon colour for a widget: per-widget override, else the kind's default when
  /// "Colourful icons" is on, else nil (inherit the label colour).
  func iconTint(for spec: WidgetSpec) -> Color? {
    switch spec.options.iconTint {
    case "none": return nil
    case "auto": return colorfulIcons ? spec.kind.defaultTint.map { stateColor($0) } : nil
    case let raw: return AccentToken(rawValue: raw).map { stateColor($0) }
    }
  }

  var hoverAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
  var stateAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.25) }

  static func resolve(appearance a: AppearanceSettings, isDark: Bool, reduceTransparency: Bool,
                      increaseContrast: Bool, reduceMotion: Bool) -> ResolvedTheme {
    var p = isDark ? Palette.dark : Palette.light
    if increaseContrast {
      p.text = isDark ? .white : .black; p.text2 = p.text.opacity(0.85); p.text3 = p.text.opacity(0.7)
      p.rim = p.rim.opacity(1); p.highlightRim = isDark ? .white : .black
    }
    let m = Metrics(barHeight: a.barHeight, pillHeight: a.pillHeight, pillRadius: a.pillRadius,
                    chipHeight: a.chipHeight, chipRadius: a.chipRadius, gap: a.gap)
    return ResolvedTheme(palette: p, metrics: m, fonts: Fonts(labelSize: a.labelFontSize, iconSize: a.iconFontSize),
                         accent: p.accent(a.accent), colorfulIcons: a.colorfulIcons, glassStyle: a.glassStyle,
                         widgetGlass: a.widgetGlass, glassClearness: a.glassClearness, isDark: isDark, reduceTransparency: reduceTransparency,
                         increaseContrast: increaseContrast, reduceMotion: reduceMotion)
  }

  static let preview = resolve(appearance: AppearanceSettings(), isDark: true, reduceTransparency: false,
                               increaseContrast: false, reduceMotion: false)
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
              blue: Double(hex & 0xff) / 255, opacity: alpha)
  }
}

extension NSColor {
  convenience init(hex: UInt32, alpha: CGFloat = 1) {
    self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
              blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
  }
}
