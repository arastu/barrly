import SwiftUI

/// SwiftUI content of one glass capsule: the surface's visible widgets in a row.
struct SurfaceView: View {
  let surfaceID: UUID
  let runtime: Runtime

  var body: some View {
    let theme = runtime.theme
    let surface = runtime.settings.settings.layout.allSurfaces.first { $0.id == surfaceID }
    HStack(spacing: 0) {
      if let surface {
        ForEach(runtime.visibleWidgets(of: surface)) { spec in
          WidgetView(spec: spec)
        }
      }
    }
    .padding(.horizontal, theme.metrics.surfacePadding)
    .frame(height: theme.metrics.pillHeight)
    .background {
      if theme.reduceTransparency {
        Capsule().fill(theme.isDark ? Color(white: 0.12) : Color(white: 0.95))
      }
    }
    .environment(runtime)
    .environment(\.theme, theme)
    .fixedSize()
  }
}
