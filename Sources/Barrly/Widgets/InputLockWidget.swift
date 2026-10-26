import SwiftUI

/// Click to block all keyboard and mouse input; the configured chord releases it. Shows only a
/// lock icon (red while locked).
struct InputLockWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme

  var body: some View {
    let lock = runtime.inputLock
    WidgetCell(spec: spec, onClick: { lock.lock() }) {
      IconLabel(symbol: lock.locked ? "lock.fill" : "lock.open.fill",
                iconColor: lock.locked ? theme.stateColor(.red) : theme.iconTint(for: spec))
      .foregroundStyle(lock.locked ? theme.stateColor(.red) : (spec.secondary ? theme.palette.text2 : theme.palette.text))
    }
    .animation(theme.stateAnimation, value: lock.locked)
    .onChange(of: spec.options.unlockChord, initial: true) { _, c in lock.chord = c }
    .onChange(of: spec.options.lockChord, initial: true) { _, c in lock.lockChord = c }
    .onChange(of: spec.options.keepAwake, initial: true) { _, v in lock.keepAwake = v }
    .onDisappear { lock.lockChord = nil }
  }
}
