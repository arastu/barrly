import AppKit

/// App icons by bundle id, resized once and cached. Main-actor only (NSImage from NSWorkspace).
@MainActor
final class AppIconCache {
  static let shared = AppIconCache()
  private var cache: [String: NSImage] = [:]

  func icon(bundleId: String, size: CGFloat = 16) -> NSImage? {
    let key = "\(bundleId)@\(size)"
    if let i = cache[key] { return i }
    var img: NSImage? = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.icon
    if img == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) { img = NSWorkspace.shared.icon(forFile: url.path) }
    guard let img else { return nil }
    let copy = img.copy() as! NSImage
    copy.size = NSSize(width: size, height: size)
    cache[key] = copy
    return copy
  }
}
