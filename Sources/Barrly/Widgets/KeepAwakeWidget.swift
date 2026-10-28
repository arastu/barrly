import SwiftUI

/// Click to keep the Mac and display awake; click again to let them sleep. An owl: eyes open and
/// lit while active (including while the input lock is holding it), asleep otherwise.
struct KeepAwakeWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme

  var body: some View {
    let awake = runtime.keepAwake
    WidgetCell(spec: spec, onClick: { awake.toggle() }) {
      OwlIcon(awake: awake.active)
        .foregroundStyle(awake.active ? theme.stateColor(.peach) : (theme.iconTint(for: spec) ?? (spec.secondary ? theme.palette.text2 : theme.palette.text)))
    }
    .animation(theme.stateAnimation, value: awake.active)
  }
}
