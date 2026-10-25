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
        Toggle("Keep below the notch", isOn: $store.settings.appearance.respectNotch)
        Picker("Displays", selection: $store.settings.appearance.displays) { Text("All displays").tag(DisplaySelection.all); Text("Main display only").tag(DisplaySelection.main) }
      }
      Section("Glass") {
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
