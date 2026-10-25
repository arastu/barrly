import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedPane: View {
  @Environment(Runtime.self) private var runtime
  @ViewState private var message: String? = nil
  @ViewState private var confirmReset = false

  var body: some View {
    @Bindable var store = runtime.settings
    Form {
      Section("Startup") {
        Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { on in
          do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; message = nil }
          catch { message = "\(error.localizedDescription)" }
        }))
        Text("Or start it from AeroSpace: after-startup-command = ['exec-and-forget open -a Barrly']").font(.caption).foregroundStyle(.secondary)
      }
      Section("Settings file") {
        HStack {
          Button("Export…") { export() }
          Button("Import…") { importFile() }
          Button("Reset to defaults", role: .destructive) { confirmReset = true }
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      }
      Section("Diagnostics") {
        LabeledContent("AeroSpace", value: runtime.aerospace.connected ? "connected (\(runtime.aerospace.events) events)" : "not connected")
        LabeledContent("Scheduler wakeups", value: "\(runtime.scheduler.wakeups)")
        LabeledContent("Now playing source", value: runtime.nowPlaying.usingAdapter ? "adapter" : "fallback")
        LabeledContent("Calendar", value: runtime.calendar.authorized ? "authorized" : "no access")
        if let err = store.loadError { Text("Settings failed to load: \(err)").font(.caption).foregroundStyle(.red) }
        Button("Quit Barrly") { NSApp.terminate(nil) }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("Reset all settings to the defaults?", isPresented: $confirmReset) { Button("Reset", role: .destructive) { runtime.settings.reset() } }
  }

  private func export() {
    let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = "barrly-settings.json"
    guard p.runModal() == .OK, let url = p.url else { return }
    do { try runtime.settings.exportJSON().write(to: url); message = "Exported to \(url.lastPathComponent)" } catch { message = "\(error)" }
  }
  private func importFile() {
    let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
    guard p.runModal() == .OK, let url = p.url else { return }
    do { try runtime.settings.importJSON(Data(contentsOf: url)); message = "Imported \(url.lastPathComponent)" } catch { message = "Import failed: \(error)" }
  }
}
