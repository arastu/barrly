import AppKit
import SwiftUI

/// Shows a key chord; click it and press the new combination. Esc cancels.
struct ShortcutRecorder: View {
  @Binding var chord: KeyChord
  @ViewState private var recording = false
  @ViewState private var monitor: Any? = nil

  var body: some View {
    HStack {
      Button(recording ? "Press keys…" : chord.display) { recording ? stop() : start() }
        .frame(minWidth: 90)
        .foregroundStyle(recording ? Color.accentColor : Color.primary)
      if recording { Button("Cancel") { stop() }.controlSize(.small) }
    }
    .onDisappear { stop() }
  }

  private func start() {
    recording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 { stop(); return nil }   // Esc
      let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
      guard !mods.isEmpty else { return nil }        // a bare key would be far too easy to hit by accident
      let label = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespaces)
      chord = KeyChord(keyCode: Int(event.keyCode), modifiers: mods.rawValue, label: label.isEmpty ? "key \(event.keyCode)" : label)
      stop()
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil; recording = false
  }
}
