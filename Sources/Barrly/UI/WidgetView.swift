import SwiftUI

/// Dispatches a WidgetSpec to its built-in view.
struct WidgetView: View {
  let spec: WidgetSpec
  var body: some View {
    switch spec.kind {
    case .appleMenu: AppleMenuWidget(spec: spec)
    case .workspaces: WorkspacesWidget(spec: spec)
    case .frontApp: FrontAppWidget(spec: spec)
    case .nowPlaying: NowPlayingWidget(spec: spec)
    case .cpu: CpuWidget(spec: spec)
    case .ram: RamWidget(spec: spec)
    case .wifi: WifiWidget(spec: spec)
    case .battery: BatteryWidget(spec: spec)
    case .jalaliDate: JalaliDateWidget(spec: spec)
    case .clock: ClockWidget(spec: spec)
    case .inputSource: InputSourceWidget(spec: spec)
    case .meeting: MeetingWidget(spec: spec)
    case .volume: VolumeWidget(spec: spec)
    case .spacer: Color.clear.frame(width: spec.options.width, height: 1)
    }
  }
}
