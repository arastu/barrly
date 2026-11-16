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
  private var spaceToken: NSObjectProtocol? = nil
  private var pointerMonitors: [Any] = []
  private var edgeDwell: DispatchWorkItem? = nil
  private var steppedAside = false

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
    spaceToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
      Task { @MainActor [weak self] in self?.updateVisibility() }
    }
    updateVisibility()
    if #available(macOS 27, *) { watchPointer() }
  }

  func attach(to screen: NSScreen) { self.screen = screen; screenID = screen.displayID; relayout(); updateVisibility() }

  func close() {
    if let spaceToken { NSWorkspace.shared.notificationCenter.removeObserver(spaceToken) }
    for m in pointerMonitors { NSEvent.removeMonitor(m) }
    pointerMonitors.removeAll(); edgeDwell?.cancel()
    panel.orderOut(nil); panel.close()
  }

  /// macOS 27 leaves the auto-hidden menu bar's window over the strip, where it takes every click and
  /// hover aimed at a window below it. There the bar sits above the menu bar instead.
  private var underHiddenMenuBar: Bool {
    guard #available(macOS 27, *) else { return false }
    return UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
  }

  private func applyLevel() {
    panel.apply(topmost: runtime.settings.settings.appearance.alwaysOnTop, aboveMenuBar: underHiddenMenuBar && !steppedAside)
  }

  /// Sitting above the menu bar would cover it when it is revealed, so the bar drops back under it
  /// once the pointer has rested on the top edge, and comes back when the pointer leaves the strip.
  private func watchPointer() {
    if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
      Task { @MainActor [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
    }) { pointerMonitors.append(m) }
    if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
      MainActor.assumeIsolated { self?.pointerMoved(to: NSEvent.mouseLocation) }
      return event
    }) { pointerMonitors.append(m) }
  }

  private func pointerMoved(to p: CGPoint) {
    let onScreen = p.x >= screen.frame.minX && p.x < screen.frame.maxX
    if steppedAside {
      guard !onScreen || p.y < panel.frame.minY - 4 else { return }
      steppedAside = false; applyLevel()
    } else if onScreen, p.y >= screen.frame.maxY - 1, underHiddenMenuBar {
      guard edgeDwell == nil else { return }
      let work = DispatchWorkItem { [weak self] in
        MainActor.assumeIsolated { self?.edgeDwell = nil; self?.steppedAside = true; self?.applyLevel() }
      }
      edgeDwell = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    } else {
      edgeDwell?.cancel(); edgeDwell = nil
    }
  }

  /// The bar steps aside while its screen shows a fullscreen Space.
  private func updateVisibility() {
    if screen.isShowingFullscreenSpace { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
  }

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
    applyLevel()
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
