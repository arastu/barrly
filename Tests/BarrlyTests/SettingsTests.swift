import Foundation
import Testing
@testable import Barrly

@Suite struct SettingsTests {
  @Test func roundTrip() throws {
    let s = Settings.default
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(Settings.self, from: data)
    #expect(back == s)
  }

  @Test func tolerantOptionsDecoding() throws {
    let json = #"{"kind":"clock","id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","enabled":true,"hiddenInZen":false,"hoverable":true,"secondary":false,"options":{"clockFormat":"HH:mm"}}"#
    let spec = try JSONDecoder().decode(WidgetSpec.self, from: Data(json.utf8))
    #expect(spec.options.clockFormat == "HH:mm")
    #expect(spec.options.maxIcons == 4) // default filled in
  }

  @Test func defaultLayoutMatchesSketchybar() {
    let l = Settings.default.layout
    #expect(l.left.map(\.name) == ["Navigation", "Now playing", "Meeting"])
    #expect(l.right.map(\.name) == ["Status"])
    #expect(l.left[2].tint == .lavender)
    #expect(l.allWidgets.filter { $0.hiddenInZen }.map(\.kind) == [.nowPlaying, .cpu, .ram, .wifi, .volume, .jalaliDate, .inputSource])
  }

  @Test func migrationMovesMeetingAfterNowPlaying() {
    var s = Settings.default
    s.version = 1
    let meeting = s.layout.left.remove(at: 2); s.layout.right.append(meeting)
    s.migrate()
    #expect(s.version == 6)
    #expect(s.layout.left.map(\.name) == ["Navigation", "Now playing", "Meeting"])
    #expect(s.layout.right.map(\.name) == ["Status"])
  }

  @Test func migrationAddsVolumeAfterWifi() {
    var s = Settings.default
    s.version = 2
    s.layout.right[0].widgets.removeAll { $0.kind == .volume }
    s.migrate()
    #expect(s.version == 6)
    let kinds = s.layout.right[0].widgets.map(\.kind)
    #expect(kinds.firstIndex(of: .volume) == kinds.firstIndex(of: .wifi).map { $0 + 1 })
    #expect(kinds.filter { $0 == .volume }.count == 1)
    s.migrate()
    #expect(kinds == s.layout.right[0].widgets.map(\.kind))
  }

  @Test func migrationAddsVPNAfterWifi() {
    var s = Settings.default
    s.version = 3
    s.layout.right[0].widgets.removeAll { $0.kind == .vpn }
    s.migrate()
    #expect(s.version == 6)
    let kinds = s.layout.right[0].widgets.map(\.kind)
    #expect(kinds.firstIndex(of: .vpn) == kinds.firstIndex(of: .wifi).map { $0 + 1 })
    #expect(kinds.filter { $0 == .vpn }.count == 1)
  }

  @Test func migrationAppendsInputLock() {
    var s = Settings.default
    s.version = 4
    s.layout.right[0].widgets.removeAll { $0.kind == .inputLock }
    s.migrate()
    #expect(s.version == 6)
    #expect(s.layout.right[0].widgets.last?.kind == .inputLock)
    #expect(s.layout.allWidgets.filter { $0.kind == .inputLock }.count == 1)
  }

  @Test func migrationInsertsKeepAwakeBeforeInputLock() {
    var s = Settings.default
    s.version = 5
    s.layout.right[0].widgets.removeAll { $0.kind == .keepAwake }
    s.migrate()
    #expect(s.version == 6)
    let kinds = s.layout.right[0].widgets.map(\.kind)
    #expect(kinds.firstIndex(of: .keepAwake) == kinds.firstIndex(of: .inputLock).map { $0 - 1 })
    #expect(kinds.filter { $0 == .keepAwake }.count == 1)
    s.migrate()
    #expect(kinds == s.layout.right[0].widgets.map(\.kind))
  }

  @Test func migrationAppendsKeepAwakeWithoutInputLock() {
    var s = Settings.default
    s.version = 5
    s.layout.right[0].widgets.removeAll { $0.kind == .keepAwake || $0.kind == .inputLock }
    s.migrate()
    #expect(s.layout.right[0].widgets.last?.kind == .keepAwake)
  }

  @Test func themeResolution() {
    let a = AppearanceSettings()
    let dark = ResolvedTheme.resolve(appearance: a, isDark: true, reduceTransparency: false, increaseContrast: false, reduceMotion: true)
    #expect(dark.isDark && dark.hoverAnimation == nil)
    let light = ResolvedTheme.resolve(appearance: a, isDark: false, reduceTransparency: true, increaseContrast: true, reduceMotion: false)
    #expect(light.reduceTransparency && light.hoverAnimation != nil)
    #expect(light.palette.accent(.mauve) != dark.palette.accent(.mauve))
  }
}
