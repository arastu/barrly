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
      } else if theme.glassStyle == .transparent {
        // See-through capsule: no blur, a faint tint (the surface tint if any), a specular rim.
        let base: Color = surface?.tint.map { theme.palette.accent($0) } ?? (theme.isDark ? .black : .white)
        let shape = RoundedRectangle(cornerRadius: theme.metrics.pillRadius, style: .continuous)
        shape.fill(base.opacity(theme.capsuleOpacity))
          .overlay(shape.fill(LinearGradient(colors: [.white.opacity(theme.isDark ? 0.08 : 0.25), .clear], startPoint: .top, endPoint: .center)))
          .overlay(shape.strokeBorder(theme.palette.rim, lineWidth: 1))
      }
    }
    .environment(runtime)
    .environment(\.theme, theme)
    .fixedSize()
  }
}
