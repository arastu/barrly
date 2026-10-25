// Spikes 1–3: Liquid Glass capsules in a borderless, non-activating NSPanel at backstop
// level, sticky across Spaces, with SwiftUI hover + click inside NSHostingView.
// Logs to /tmp/glasspanel.log so results can be read without watching the screen.
import AppKit
import SwiftUI

let logURL = URL(fileURLWithPath: "/tmp/glasspanel.log")
func log(_ s: String) {
  let line = "\(Date()) \(s)\n"; print(line, terminator: "")
  if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
  else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

@MainActor final class BarPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor @Observable final class Model {
  var hovered: String? = nil
  var clicks = 0
  var tick = 0
}

struct Cell: View {
  let name: String; @Bindable var model: Model
  var body: some View {
    let on = model.hovered == name
    HStack(spacing: 6) {
      Image(systemName: name == "clock" ? "calendar" : "apple.logo").font(.system(size: 14, weight: .medium))
      if name == "clock" { Text(Date.now.formatted(date: .abbreviated, time: .shortened) + "  \(model.tick)").font(.system(size: 13, weight: .semibold)) }
    }
    .padding(.horizontal, 10).frame(height: 22)
    .background(Capsule().fill(.white.opacity(on ? 0.35 : 0)).overlay(Capsule().strokeBorder(.white.opacity(on ? 0.45 : 0), lineWidth: 1)))
    .animation(.easeInOut(duration: 0.2), value: on)
    .contentShape(Rectangle())
    .onHover { h in model.hovered = h ? name : (model.hovered == name ? nil : model.hovered); log("hover \(name) \(h) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")") }
    .onTapGesture { model.clicks += 1; log("click \(name) #\(model.clicks) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") active=\(NSApp.isActive)") }
  }
}

struct Surface: View {
  @Bindable var model: Model
  var body: some View { HStack(spacing: 4) { Cell(name: "apple", model: model); Cell(name: "clock", model: model) }.padding(.horizontal, 4).frame(height: 30) }
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
  var panels: [BarPanel] = []; let model = Model()
  func applicationDidFinishLaunching(_ n: Notification) {
    try? FileManager.default.removeItem(at: logURL)
    NSApp.setActivationPolicy(.accessory)
    let topmost = CommandLine.arguments.contains("--topmost")
    for screen in NSScreen.screens {
      let h: CGFloat = 38, margin: CGFloat = 6, yOff: CGFloat = 6
      let autoHide = UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
      let menuInset = autoHide ? 0 : (screen.frame.maxY - screen.visibleFrame.maxY)
      let frame = CGRect(x: screen.frame.minX + margin, y: screen.frame.maxY - menuInset - yOff - h, width: screen.frame.width - 2*margin, height: h)
      let p = BarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.isFloatingPanel = true; p.hidesOnDeactivate = false; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
      p.level = topmost ? .statusBar : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.backstopMenu)))
      p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
      p.isMovableByWindowBackground = false; p.animationBehavior = .none

      let container = NSGlassEffectContainerView(frame: p.contentView!.bounds); container.autoresizingMask = [.width, .height]; container.spacing = 10
      let content = NSView(frame: container.bounds); content.autoresizingMask = [.width, .height]; container.contentView = content
      func capsule(x: CGFloat, w: CGFloat, tint: NSColor?) -> NSGlassEffectView {
        let g = NSGlassEffectView(frame: CGRect(x: x, y: 4, width: w, height: 30))
        g.cornerRadius = 15; g.style = .regular; g.tintColor = tint
        let host = NSHostingView(rootView: Surface(model: model)); host.frame = g.bounds; host.autoresizingMask = [.width, .height]
        g.contentView = host; return g
      }
      content.addSubview(capsule(x: 4, w: 220, tint: nil))
      content.addSubview(capsule(x: frame.width - 224, w: 220, tint: NSColor.systemPurple.withAlphaComponent(0.25)))
      p.contentView = container
      p.orderFrontRegardless(); panels.append(p)
      log("panel on screen \(screen.localizedName) frame=\(frame) level=\(p.level.rawValue) menuInset=\(menuInset) safeTop=\(screen.safeAreaInsets.top)")
    }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [model] _ in Task { @MainActor in model.tick += 1 } }
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in log("appearance changed") }
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in log("space changed; visible=\(self?.panels.map { $0.isVisible } ?? []) onActiveSpace=\(self?.panels.map { $0.isOnActiveSpace } ?? [])") } }
  }
}

let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.run()
