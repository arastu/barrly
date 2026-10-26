import AppKit
import SwiftUI

/// Shows a key chord; click it and press the new combination. Esc cancels.
struct ShortcutRecorder: View {
  @Binding var chord: KeyChord?
  var allowNone = false
  var onRecording: (Bool) -> Void = { _ in }
  @ViewState private var recording = false
  @ViewState private var monitor: Any? = nil

  init(chord: Binding<KeyChord?>, allowNone: Bool = true, onRecording: @escaping (Bool) -> Void = { _ in }) {
    _chord = chord; self.allowNone = allowNone; self.onRecording = onRecording
  }
  init(chord: Binding<KeyChord>, onRecording: @escaping (Bool) -> Void = { _ in }) {
    _chord = Binding<KeyChord?>(get: { chord.wrappedValue }, set: { if let v = $0 { chord.wrappedValue = v } })
    allowNone = false; self.onRecording = onRecording
  }

  var body: some View {
    HStack {
      Button(recording ? "Press keys…" : (chord?.display ?? "None")) { recording ? stop() : start() }
        .frame(minWidth: 90)
        .foregroundStyle(recording ? Color.accentColor : Color.primary)
      if recording { Button("Cancel") { stop() }.controlSize(.small) }
      else if allowNone && chord != nil { Button("Clear") { chord = nil }.controlSize(.small) }
    }
    .onDisappear { stop() }
  }

  private func start() {
    recording = true; onRecording(true)
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
    monitor = nil
    if recording { recording = false; onRecording(false) }
  }
}
