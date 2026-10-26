import SwiftUI

struct AppearancePane: View {
  @Environment(Runtime.self) private var runtime
  var body: some View {
    @Bindable var store = runtime.settings
    Form {
      Section("Bar") {
        Slider(value: $store.settings.appearance.barHeight, in: 24...56, step: 1) { Text("Height: \(Int(store.settings.appearance.barHeight)) pt") }
        Slider(value: $store.settings.appearance.margin, in: 0...24, step: 1) { Text("Side margin: \(Int(store.settings.appearance.margin)) pt") }
        Slider(value: $store.settings.appearance.yOffset, in: 0...24, step: 1) { Text("Top offset: \(Int(store.settings.appearance.yOffset)) pt") }
        Toggle("Always on top of windows", isOn: $store.settings.appearance.alwaysOnTop)
        Text("Stays below the system menu bar, so an auto-hidden menu bar still slides over it.").font(.caption).foregroundStyle(.secondary)
        Toggle("Keep below the notch", isOn: $store.settings.appearance.respectNotch)
        Picker("Displays", selection: $store.settings.appearance.displays) { Text("All displays").tag(DisplaySelection.all); Text("Main display only").tag(DisplaySelection.main) }
      }
      Section("Glass") {
        Picker("Bar appearance", selection: $store.settings.appearance.barAppearance) { Text("Follow system").tag(BarAppearance.system); Text("Light").tag(BarAppearance.light); Text("Dark").tag(BarAppearance.dark) }
        Text("Dark with clear glass is the look of the system volume and brightness HUD.").font(.caption).foregroundStyle(.secondary)
        Picker("Glass", selection: $store.settings.appearance.glassStyle) { Text("Clear (like the Dock)").tag(GlassStyle.clear); Text("Regular (frosted)").tag(GlassStyle.regular) }
        Toggle("Glass behind every widget", isOn: $store.settings.appearance.widgetGlass)
        Slider(value: $store.settings.appearance.pillHeight, in: 20...48, step: 1) { Text("Capsule height: \(Int(store.settings.appearance.pillHeight)) pt") }
        Slider(value: $store.settings.appearance.pillRadius, in: 0...24, step: 1) { Text("Capsule radius: \(Int(store.settings.appearance.pillRadius)) pt") }
        Slider(value: $store.settings.appearance.chipHeight, in: 14...40, step: 1) { Text("Chip height: \(Int(store.settings.appearance.chipHeight)) pt") }
        Slider(value: $store.settings.appearance.chipRadius, in: 0...20, step: 1) { Text("Chip radius: \(Int(store.settings.appearance.chipRadius)) pt") }
        Slider(value: $store.settings.appearance.gap, in: 0...24, step: 1) { Text("Gap between capsules: \(Int(store.settings.appearance.gap)) pt") }
        Text("Concentric corners: chip radius ≈ capsule radius − (capsule − chip height) / 2.").font(.caption).foregroundStyle(.secondary)
      }
      Section("Type") {
        Slider(value: $store.settings.appearance.labelFontSize, in: 10...18, step: 1) { Text("Label size: \(Int(store.settings.appearance.labelFontSize)) pt") }
        Slider(value: $store.settings.appearance.iconFontSize, in: 10...20, step: 1) { Text("Symbol size: \(Int(store.settings.appearance.iconFontSize)) pt") }
        Picker("Accent", selection: $store.settings.appearance.accent) { ForEach(AccentToken.allCases) { Text($0.rawValue.capitalized).tag($0) } }
        Toggle("Colourful icons", isOn: $store.settings.appearance.colorfulIcons)
        Text("Each widget's symbol gets its own colour; override per widget in its options.").font(.caption).foregroundStyle(.secondary)
      }
      Section("System") {
        LabeledContent("Appearance", value: runtime.appearance.isDark ? "Dark" : "Light")
        LabeledContent("Reduce transparency", value: runtime.appearance.reduceTransparency ? "On" : "Off")
        LabeledContent("Reduce motion", value: runtime.appearance.reduceMotion ? "On" : "Off")
        Text("Barrly follows the system: light and dark glass, opaque fills with Reduce Transparency, no fades with Reduce Motion.").font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
