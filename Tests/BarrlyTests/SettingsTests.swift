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
    #expect(l.left.map(\.name) == ["Navigation", "Now playing"])
    #expect(l.right.map(\.name) == ["Status", "Meeting"])
    #expect(l.right[1].tint == .lavender)
    #expect(l.allWidgets.filter { $0.hiddenInZen }.map(\.kind) == [.nowPlaying, .cpu, .ram, .wifi, .jalaliDate, .inputSource])
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
