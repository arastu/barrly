import AppKit
import Observation
import SwiftUI

/// The AppKit shell for one screen: panel, glass container, three stacks of glass capsules.
/// Structure (which surfaces exist, their order and tint) is rebuilt from Settings; everything
/// inside a capsule is SwiftUI and updates itself.
@MainActor
final class BarWindowController {
  let runtime: Runtime
  private(set) var screenID: CGDirectDisplayID
  private var screen: NSScreen
  private let panel: BarPanel
  private let container = NSGlassEffectContainerView()
  private let root = NSView()
  private var stacks: [Side: NSStackView] = [:]
  private var glass: [UUID: GlassSurfaceView] = [:]
  private var structure: [Side: [UUID]] = [:]

  init(runtime: Runtime, screen: NSScreen) {
    self.runtime = runtime; self.screen = screen; self.screenID = screen.displayID
    panel = BarPanel(frame: Self.frame(for: screen, appearance: runtime.settings.settings.appearance))
    container.translatesAutoresizingMaskIntoConstraints = false
    container.spacing = 10
    root.translatesAutoresizingMaskIntoConstraints = false
    container.contentView = root
    panel.contentView = container
    if let cv = panel.contentView {
      NSLayoutConstraint.activate([
        container.leadingAnchor.constraint(equalTo: cv.leadingAnchor), container.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
        container.topAnchor.constraint(equalTo: cv.topAnchor), container.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        root.leadingAnchor.constraint(equalTo: container.leadingAnchor), root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        root.topAnchor.constraint(equalTo: container.topAnchor), root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }
    for side in Side.allCases {
      let s = NSStackView(); s.orientation = .horizontal; s.alignment = .centerY; s.distribution = .fill
      s.translatesAutoresizingMaskIntoConstraints = false; s.detachesHiddenViews = true
      root.addSubview(s); stacks[side] = s
      s.centerYAnchor.constraint(equalTo: root.centerYAnchor).isActive = true
      switch side {
      case .left: s.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4).isActive = true
      case .center: s.centerXAnchor.constraint(equalTo: root.centerXAnchor).isActive = true
      case .right: s.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4).isActive = true
      }
    }
    observe()
    panel.orderFrontRegardless()
  }

  func attach(to screen: NSScreen) { self.screen = screen; screenID = screen.displayID; relayout() }

  func close() { panel.orderOut(nil); panel.close() }

  /// Position: the bar lives in the (auto-hidden) menu bar strip unless the menu bar is visible.
  static func frame(for screen: NSScreen, appearance a: AppearanceSettings) -> CGRect {
    let autoHide = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    var topInset: CGFloat = autoHide ? 0 : (screen.frame.maxY - screen.visibleFrame.maxY)
    if a.respectNotch { topInset = max(topInset, screen.safeAreaInsets.top) }
    return CGRect(x: screen.frame.minX + a.margin, y: screen.frame.maxY - topInset - a.yOffset - a.barHeight,
                  width: screen.frame.width - 2 * a.margin, height: a.barHeight)
  }

  private func observe() {
    withObservationTracking {
      apply()
    } onChange: {
      Task { @MainActor [weak self] in self?.observe() }
    }
  }

  /// Reads everything structural and pushes it into AppKit. Cheap; runs on any tracked change.
  private func apply() {
    let settings = runtime.settings.settings
    let theme = runtime.theme
    relayout(appearance: settings.appearance)
    panel.apply(topmost: settings.appearance.alwaysOnTop)
    for side in Side.allCases {
      let surfaces = settings.layout[side]
      let ids = surfaces.map(\.id)
      let stack = stacks[side]!
      stack.spacing = theme.metrics.gap
      if structure[side] != ids {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for s in surfaces {
          let g = glass[s.id] ?? GlassSurfaceView(surfaceID: s.id, runtime: runtime)
          glass[s.id] = g; stack.addArrangedSubview(g)
        }
        structure[side] = ids
      }
      for s in surfaces {
        guard let g = glass[s.id] else { continue }
        g.apply(theme: theme, tint: s.tint)
        g.isHidden = !runtime.isSurfaceVisible(s)
      }
    }
    let live = Set(settings.layout.allSurfaces.map(\.id))
    for (id, g) in glass where !live.contains(id) { g.removeFromSuperview(); glass[id] = nil }
  }

  private func relayout(appearance: AppearanceSettings? = nil) {
    let a = appearance ?? runtime.settings.settings.appearance
    let f = Self.frame(for: screen, appearance: a)
    if panel.frame != f { panel.setFrame(f, display: true) }
  }
}
