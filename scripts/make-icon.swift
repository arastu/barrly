// make-icon.swift <source.png> <out-dir>
// Crops the artwork's rounded square out of its background, fits it to the macOS icon grid
// (824 pt squircle on a 1024 canvas, transparent outside) and writes AppIcon.iconset + AppIcon.icns.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]), let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  print("usage: make-icon.swift <source.png> <out-dir>"); exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// 1. Find the artwork: pixels that are clearly coloured (the glass square), ignoring the pale shadow/background.
let w = cg.width, h = cg.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w {
  let i = (y * w + x) * 4
  let r = Double(px[i]) / 255, g = Double(px[i+1]) / 255, b = Double(px[i+2]) / 255, a = Double(px[i+3]) / 255
  guard a > 0.5 else { continue }
  let mx = max(r, g, b), mn = min(r, g, b)
  let sat = mx == 0 ? 0 : (mx - mn) / mx
  // Strongly coloured only: the saturated body of the artwork, never the pale halo or the shadow.
  if sat > 0.45 || mx < 0.5 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
}}
// The saturated body spans the full width and reaches the bottom edge; the top may be pale,
// so derive it from the width (the artwork is square). CG rows count from the bottom.
let side = maxX - minX + 1
let crop = CGRect(x: minX, y: minY, width: side, height: side)
print("artwork bbox: \(crop)")
guard let cropped = cg.cropping(to: crop) else { exit(1) }

// 2. Compose onto the icon grid with a continuous-corner (squircle) mask.
func render(_ size: Int) -> CGImage {
  let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let s = CGFloat(size)
  let inset = s * (100.0 / 1024.0)                 // Apple's grid: 824 pt artwork on 1024
  let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
  let radius = rect.width * 0.2237                 // macOS squircle corner ratio
  let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
  c.addPath(path); c.clip()
  c.interpolationQuality = .high
  c.draw(cropped, in: rect)
  return c.makeImage()!
}

func write(_ img: CGImage, _ url: URL) {
  let rep = NSBitmapImageRep(cgImage: img)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  write(render(base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
  write(render(base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
write(render(1024), outDir.appendingPathComponent("AppIcon-1024.png"))
print("wrote \(iconset.path)")
