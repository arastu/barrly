import AppKit
import SwiftUI

/// Output volume: speaker icon with the level, percentage label. Click toggles mute, scrolling over it changes the level.
struct VolumeWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var hovered = false
  @ViewState private var scroll = ScrollMonitor()

  var body: some View {
    let v = runtime.volume.state
    let silent = v.muted || v.level <= 0.004
    let symbol = silent ? "speaker.slash.fill" : v.level < 0.34 ? "speaker.wave.1.fill" : v.level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    let percent = Int((v.level * 100).rounded())
    WidgetCell(spec: spec, onClick: { runtime.volume.toggleMute() }) {
      IconLabel(symbol: symbol,
                label: spec.options.showPercent ? (v.muted ? "mute" : "\(percent)%") : nil,
                iconColor: silent ? theme.palette.text3 : theme.iconTint(for: spec))
      .foregroundStyle(silent ? theme.palette.text3 : (spec.secondary ? theme.palette.text2 : theme.palette.text))
      .contentTransition(.numericText())
    }
    .animation(theme.stateAnimation, value: silent)
    .onHover { hovered = $0; scroll.active = $0 }
    .onAppear { scroll.start { steps in runtime.volume.adjust(byPercent: steps * max(1, spec.options.volumeStep)) } }
    .onDisappear { scroll.stop() }
  }
}

/// Turns scroll-wheel events over the hovered cell into ±1 steps. One local monitor per widget instance;
/// it only does work while the cursor is over the cell, so the cost is nil the rest of the time.
@MainActor
final class ScrollMonitor {
  var active = false
  private var token: Any? = nil
  private var accumulated: Double = 0

  func start(_ onStep: @escaping (Int) -> Void) {
    stop()
    token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.active else { return event }
      if event.phase == .began || event.momentumPhase == .began { self.accumulated = 0 }
      if event.momentumPhase != [] && event.momentumPhase != .began { return nil } // ignore trackpad inertia
      // Precise (trackpad) deltas are points; wheel deltas are lines. Normalise to roughly one step per flick.
      self.accumulated += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
      let steps = Int(self.accumulated.rounded(.towardZero))
      if steps != 0 { self.accumulated -= Double(steps); onStep(steps) }
      return nil
    }
  }

  func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
}
