import AppKit
import Observation
import os

/// Owns every long-lived object: stores, providers, scheduler. Views reach it through the Environment.
@MainActor @Observable
final class Runtime {
  let settings: SettingsStore
  let modes = ModeStore()
  let appearance: AppearanceModel
  let scheduler = Scheduler()
  let log = Logger(subsystem: "dev.barrly", category: "runtime")

  let clock: ClockProvider
  let frontApp = FrontAppProvider()
  let cpu: CpuProvider
  let memory: MemoryProvider
  let battery: BatteryProvider
  let inputSource = InputSourceProvider()
  let network = NetworkProvider()
  let aerospace = AerospaceProvider()
  let keepAwake = KeepAwakeProvider()
  let inputLock: InputLockProvider
  @ObservationIgnored private var _nowPlaying: NowPlayingProvider? = nil
  @ObservationIgnored private var _calendar: CalendarProvider? = nil
  @ObservationIgnored private var _volume: VolumeProvider? = nil
  @ObservationIgnored private var _vpn: VPNProvider? = nil

  var nowPlaying: NowPlayingProvider { if _nowPlaying == nil { _nowPlaying = NowPlayingProvider(scheduler: scheduler) }; return _nowPlaying! }
  var calendar: CalendarProvider { if _calendar == nil { _calendar = CalendarProvider(scheduler: scheduler) }; return _calendar! }
  var volume: VolumeProvider { if _volume == nil { _volume = VolumeProvider() }; return _volume! }
  var vpn: VPNProvider { if _vpn == nil { _vpn = VPNProvider(scheduler: scheduler) }; return _vpn! }

  init(settings: SettingsStore = SettingsStore()) {
    self.settings = settings
    self.appearance = AppearanceModel()
    clock = ClockProvider(scheduler: scheduler)
    cpu = CpuProvider(scheduler: scheduler)
    memory = MemoryProvider(scheduler: scheduler)
    battery = BatteryProvider(scheduler: scheduler)
    inputLock = InputLockProvider(awake: keepAwake)
  }

  var theme: ResolvedTheme {
    ResolvedTheme.resolve(appearance: settings.settings.appearance, isDark: appearance.isDark,
                          reduceTransparency: appearance.reduceTransparency,
                          increaseContrast: appearance.increaseContrast, reduceMotion: appearance.reduceMotion)
  }

  /// Whether a placed widget currently shows anything.
  func isPresent(_ spec: WidgetSpec) -> Bool {
    guard spec.enabled else { return false }
    if modes.zen && spec.hiddenInZen { return false }
    switch spec.kind {
    case .nowPlaying: return nowPlaying.state.isPlaying && (spec.options.includeBrowsers || !nowPlaying.state.isBrowser)
    case .meeting: return calendar.meeting != nil
    case .battery: return battery.state.present
    case .workspaces: return !aerospace.workspaces.isEmpty
    case .frontApp: return frontApp.app != nil
    case .volume: return volume.state.present
    case .vpn: return vpn.state.active
    default: return true
    }
  }

  /// Visible widgets of a surface with dangling / doubled spacers removed.
  func visibleWidgets(of surface: Surface) -> [WidgetSpec] {
    var out: [WidgetSpec] = []
    for w in surface.widgets where isPresent(w) {
      if w.kind == .spacer { if out.isEmpty || out.last?.kind == .spacer { continue } }
      out.append(w)
    }
    while out.last?.kind == .spacer { out.removeLast() }
    return out
  }

  func isSurfaceVisible(_ surface: Surface) -> Bool { visibleWidgets(of: surface).contains { $0.kind != .spacer } }

  /// Stop child processes before exit.
  func shutdown() { _nowPlaying?.stop(); inputLock.unlock(); keepAwake.setManual(false) }

  /// Refresh everything (Apple menu click).
  func refreshAll() {
    scheduler.fireAll()
    aerospace.refreshNow()
    inputSource.refresh(); network.refresh(); battery.refresh(); appearance.refresh(); _volume?.refresh(); _vpn?.reloadServices()
  }

  /// Open an app by display name ("Calendar", "Activity Monitor") or bundle id. No shell involved.
  func open(app: String) {
    let ws = NSWorkspace.shared
    var url: URL? = nil
    if app.contains(".") { url = ws.urlForApplication(withBundleIdentifier: app) }
    if url == nil {
      let candidates = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                        NSHomeDirectory() + "/Applications", "/Applications/Utilities"]
      for dir in candidates {
        let p = "\(dir)/\(app).app"
        if FileManager.default.fileExists(atPath: p) { url = URL(fileURLWithPath: p); break }
      }
    }
    guard let url else { log.warning("app not found: \(app)"); return }
    ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  func handle(url: URL) {
    guard url.scheme == "barrly" else { return }
    let path = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
    switch path.joined(separator: "/") {
    case "mode/zen": modes.toggleZen()
    case "mode/zen/on": modes.zen = true
    case "mode/zen/off": modes.zen = false
    case "refresh": refreshAll()
    case "lock": inputLock.toggle()
    case "lock/on": inputLock.lock()
    case "lock/off": inputLock.unlock()
    case "awake": keepAwake.toggle()
    case "awake/on": keepAwake.setManual(true)
    case "awake/off": keepAwake.setManual(false)
    case "settings": showSettings()
    default: log.warning("unknown url: \(url)")
    }
  }

  func showSettings() { SettingsWindowController.shared.show(runtime: self) }
}
