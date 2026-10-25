import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      WidgetsPane().tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
      AppearancePane().tabItem { Label("Appearance", systemImage: "paintpalette") }
      ModesPane().tabItem { Label("Modes", systemImage: "moon.zzz") }
      AdvancedPane().tabItem { Label("Advanced", systemImage: "gearshape.2") }
    }
    .frame(minWidth: 640, minHeight: 460)
  }
}
