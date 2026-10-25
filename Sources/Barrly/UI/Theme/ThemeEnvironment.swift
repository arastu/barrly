import SwiftUI

private struct ThemeKey: EnvironmentKey { static let defaultValue: ResolvedTheme = .preview }
extension EnvironmentValues {
  var theme: ResolvedTheme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}
