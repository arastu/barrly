import Carbon
import Foundation
import Observation

struct InputSourceState: Hashable, Sendable {
  var id: String
  var languageCode: String
}

@MainActor @Observable
final class InputSourceProvider {
  private(set) var state = InputSourceState(id: "", languageCode: "en")
  @ObservationIgnored private var token: NSObjectProtocol? = nil

  init() {
    refresh()
    token = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
    ) { _ in Task { @MainActor [weak self] in self?.refresh() } }
  }

  func refresh() {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
    let id = Self.property(src, kTISPropertyInputSourceID) as? String ?? ""
    let langs = Self.property(src, kTISPropertyInputSourceLanguages) as? [String] ?? []
    let s = InputSourceState(id: id, languageCode: langs.first ?? "en")
    if s != state { state = s }
  }

  private static func property(_ src: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
  }
}
