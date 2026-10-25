import SwiftUI

struct ModesPane: View {
  @Environment(Runtime.self) private var runtime
  var body: some View {
    @Bindable var modes = runtime.modes
    Form {
      Section("Zen") {
        Toggle("Zen mode", isOn: $modes.zen)
        Text("Hides the widgets marked \"Hide in zen mode\". Toggle from anywhere with:").font(.caption).foregroundStyle(.secondary)
        Text("open barrly://mode/zen").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
      }
      Section("Hidden in zen") {
        ForEach(runtime.settings.settings.layout.allWidgets.filter { $0.kind != .spacer }) { w in
          Toggle(w.kind.title, isOn: Binding(get: { w.hiddenInZen }, set: { v in runtime.settings.update(w.id) { $0.hiddenInZen = v } }))
        }
      }
      Section("URL scheme") {
        ForEach(["barrly://mode/zen", "barrly://mode/zen/on", "barrly://mode/zen/off", "barrly://refresh", "barrly://settings"], id: \.self) {
          Text($0).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
      }
    }.formStyle(.grouped)
  }
}
