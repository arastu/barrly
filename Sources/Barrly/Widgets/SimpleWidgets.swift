import SwiftUI

struct AppleMenuWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  var body: some View {
    WidgetCell(spec: spec, onClick: { runtime.refreshAll() }, onRightClick: { runtime.showSettings() }) {
      Image(systemName: "apple.logo").font(theme.fonts.iconLarge).padding(.horizontal, 2)
    }
  }
}

struct FrontAppWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  var body: some View {
    let p = runtime.frontApp
    WidgetCell(spec: spec) {
      IconLabel(symbol: spec.options.showIcon && p.icon == nil ? "macwindow" : nil,
                image: spec.options.showIcon ? p.icon.map { Self.sized($0) } : nil,
                label: spec.options.showName ? p.app?.name : nil)
    }
  }
  static func sized(_ i: NSImage) -> NSImage { let c = i.copy() as! NSImage; c.size = NSSize(width: 16, height: 16); return c }
}

struct ClockWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  var body: some View {
    let f = DateFormatter(); f.dateFormat = spec.options.clockFormat
    if spec.options.clockFormat.contains("s") { runtime.clock.requireSeconds() }
    return WidgetCell(spec: spec, onClick: { runtime.open(app: spec.options.clickApp ?? "Calendar") }) {
      IconLabel(symbol: "calendar", label: f.string(from: runtime.clock.now))
    }
  }
}

struct JalaliDateWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  var body: some View {
    let now = runtime.clock.now
    let j = JalaliDate(now)
    let weekday = Calendar.current.component(.weekday, from: now)
    WidgetCell(spec: spec, onClick: { runtime.open(app: spec.options.clickApp ?? "Calendar") }) {
      IconLabel(symbol: "calendar", label: j.formatted(spec.options.jalaliFormat, persianDigits: spec.options.persianDigits, weekday: weekday),
                labelFont: theme.fonts.persian)
    }
  }
}

struct CpuWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  var body: some View {
    WidgetCell(spec: spec, onClick: { runtime.open(app: spec.options.clickApp ?? "Activity Monitor") }) {
      IconLabel(symbol: "cpu", label: "\(Int((runtime.cpu.usage * 100).rounded()))%")
    }
    .onChange(of: spec.options.interval, initial: true) { _, v in runtime.cpu.setInterval(max(1, v)) }
  }
}

struct RamWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  var body: some View {
    WidgetCell(spec: spec, onClick: { runtime.open(app: spec.options.clickApp ?? "Activity Monitor") }) {
      IconLabel(symbol: "memorychip", label: "\(Int((runtime.memory.usedFraction * 100).rounded()))%")
    }
    .onChange(of: spec.options.interval, initial: true) { _, v in runtime.memory.setInterval(max(1, v)) }
  }
}

struct WifiWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  @ViewState private var flash = false
  var body: some View {
    let n = runtime.network.state
    let label: String? = {
      guard let ip = n.ipv4 else { return "off" }
      if flash { return ip }
      switch spec.options.wifiShow { case .lastOctet: return "." + (ip.split(separator: ".").last.map(String.init) ?? ip); case .fullIP: return ip; case .none: return nil }
    }()
    WidgetCell(spec: spec, onClick: { copy(n.ipv4) }) {
      IconLabel(symbol: n.connected ? (n.isWifi ? "wifi" : "network") : "wifi.slash", label: label,
                iconColor: n.connected ? (flash ? theme.stateColor(.green) : nil) : theme.palette.text3)
      .foregroundStyle(flash ? theme.stateColor(.green) : (n.connected ? theme.palette.text : theme.palette.text3))
    }
  }
  private func copy(_ ip: String?) {
    guard let ip else { return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ip, forType: .string)
    withAnimation(theme.stateAnimation) { flash = true }
    Task { try? await Task.sleep(for: .seconds(2)); withAnimation(theme.stateAnimation) { flash = false } }
  }
}

struct BatteryWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  var body: some View {
    let b = runtime.battery.state
    let symbol: String = b.isCharging || (b.isPluggedIn && b.percent >= 95) ? "bolt.fill"
      : b.percent >= 88 ? "battery.100percent" : b.percent >= 63 ? "battery.75percent"
      : b.percent >= 38 ? "battery.50percent" : b.percent >= 13 ? "battery.25percent" : "battery.0percent"
    let color: Color? = b.isCharging ? theme.stateColor(.teal) : b.percent <= spec.options.warnBelow ? theme.stateColor(.red) : nil
    WidgetCell(spec: spec) {
      IconLabel(symbol: symbol, label: spec.options.showPercent ? "\(b.percent)%" : nil, iconColor: color)
    }
    .animation(theme.stateAnimation, value: color)
  }
}

struct InputSourceWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  var body: some View {
    let s = runtime.inputSource.state
    let label = spec.options.inputSourceMap[s.id]
      ?? (s.id.localizedCaseInsensitiveContains("persian") || s.id.localizedCaseInsensitiveContains("farsi") ? "FA" : nil)
      ?? String(s.languageCode.prefix(2)).uppercased()
    WidgetCell(spec: spec) { IconLabel(symbol: "keyboard", label: label, labelFont: theme.fonts.small) }
  }
}

struct NowPlayingWidget: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime
  @Environment(\.theme) private var theme
  var body: some View {
    let s = runtime.nowPlaying.state
    var text = spec.options.nowPlayingFormat.replacingOccurrences(of: "{title}", with: s.title).replacingOccurrences(of: "{artist}", with: s.artist)
    if s.artist.isEmpty { text = s.title }
    if text.count > spec.options.maxChars { text = String(text.prefix(spec.options.maxChars - 1)) + "…" }
    return WidgetCell(spec: spec, onClick: { runtime.nowPlaying.activatePlayer() }) {
      IconLabel(symbol: "music.note", label: text, labelFont: theme.fonts.labelMedium)
    }
  }
}
