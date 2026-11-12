import AppKit

// Private window-server calls: the only way to ask which kind of Space a display is showing.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

extension NSScreen {
  /// True while this screen's current Space is a native fullscreen one (video, games, fullscreen apps).
  var isShowingFullscreenSpace: Bool {
    guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return false }
    let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    // With "Displays have separate Spaces" off there is a single entry named "Main".
    let entry = displays.first { ($0["Display Identifier"] as? String) == uuid } ?? (displays.count == 1 ? displays[0] : nil)
    return ((entry?["Current Space"] as? [String: Any])?["type"] as? Int) == 4
  }
}
