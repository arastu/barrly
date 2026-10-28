import AppKit
import SwiftUI

/// A small owl, drawn in code because SF Symbols has no owl. Awake: round open eyes with pupils.
/// Asleep: closed lids. Eyes and beak are holes (even-odd fill), so the glyph is a single tintable
/// silhouette like a monochrome SF Symbol.
struct OwlShape: Shape {
  var awake: Bool

  func path(in rect: CGRect) -> Path {
    var p = Path()
    // Silhouette: ear tufts, round head, rounded body, in a unit square (y down).
    p.move(to: CGPoint(x: 0.08, y: 0.0))
    p.addLine(to: CGPoint(x: 0.31, y: 0.17))
    p.addQuadCurve(to: CGPoint(x: 0.69, y: 0.17), control: CGPoint(x: 0.50, y: 0.07))
    p.addLine(to: CGPoint(x: 0.92, y: 0.0))
    p.addLine(to: CGPoint(x: 0.98, y: 0.32))
    p.addCurve(to: CGPoint(x: 0.50, y: 1.0), control1: CGPoint(x: 1.02, y: 0.72), control2: CGPoint(x: 0.82, y: 1.0))
    p.addCurve(to: CGPoint(x: 0.02, y: 0.32), control1: CGPoint(x: 0.18, y: 1.0), control2: CGPoint(x: -0.02, y: 0.72))
    p.closeSubpath()

    for cx in [0.33, 0.67] {
      let eye = CGPoint(x: cx, y: 0.46)
      if awake {
        p.addEllipse(in: CGRect(x: eye.x - 0.16, y: eye.y - 0.16, width: 0.32, height: 0.32))
        p.addEllipse(in: CGRect(x: eye.x - 0.07, y: eye.y - 0.06, width: 0.14, height: 0.14))
      } else {
        var lid = Path()
        lid.addArc(center: CGPoint(x: eye.x, y: eye.y + 0.05), radius: 0.13,
                   startAngle: .degrees(205), endAngle: .degrees(335), clockwise: false)
        p.addPath(lid.strokedPath(StrokeStyle(lineWidth: 0.07, lineCap: .round)))
      }
    }
    // Beak.
    p.move(to: CGPoint(x: 0.44, y: 0.62))
    p.addLine(to: CGPoint(x: 0.56, y: 0.62))
    p.addLine(to: CGPoint(x: 0.50, y: 0.75))
    p.closeSubpath()

    return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
  }

  /// Template image (tints with the surrounding text colour) for AppKit-backed places such as menus.
  static func templateImage(awake: Bool, size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
      guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
      ctx.addPath(OwlShape(awake: awake).path(in: rect).cgPath)
      ctx.fillPath(using: .evenOdd)
      return true
    }
    img.isTemplate = true
    return img
  }
}

/// The owl sized like an SF Symbol at the theme's icon font size; takes the current foreground style.
struct OwlIcon: View {
  var awake: Bool
  @Environment(\.theme) private var theme
  var body: some View {
    let side = theme.fonts.iconSize * 1.05
    OwlShape(awake: awake).fill(style: FillStyle(eoFill: true)).frame(width: side, height: side)
  }
}
