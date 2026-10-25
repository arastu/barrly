import Foundation
import Observation

/// Single source of truth for user settings. Persisted as JSON in UserDefaults; changes apply live.
@MainActor @Observable
final class SettingsStore {
  static let key = "settings.v1"
  private(set) var loadError: String? = nil

  var settings: Settings {
    didSet { if settings != oldValue { scheduleSave() } }
  }

  private var saveTask: Task<Void, Never>? = nil
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.key) {
      do { settings = try JSONDecoder().decode(Settings.self, from: data) }
      catch { settings = .default; loadError = "\(error)" }
    } else {
      settings = .default
    }
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled, let self else { return }
      self.saveNow()
    }
  }

  func saveNow() {
    if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
  }

  func reset() { settings = .default }

  func exportJSON() throws -> Data {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try enc.encode(settings)
  }

  func importJSON(_ data: Data) throws {
    settings = try JSONDecoder().decode(Settings.self, from: data)
  }

  // MARK: - Widget helpers used by Settings UI and the bar

  func spec(id: UUID) -> WidgetSpec? { settings.layout.allWidgets.first { $0.id == id } }

  func update(_ id: UUID, _ edit: (inout WidgetSpec) -> Void) {
    for side in Side.allCases {
      for s in settings.layout[side].indices {
        if let w = settings.layout[side][s].widgets.firstIndex(where: { $0.id == id }) {
          edit(&settings.layout[side][s].widgets[w]); return
        }
      }
    }
  }

  func updateSurface(_ id: UUID, _ edit: (inout Surface) -> Void) {
    for side in Side.allCases {
      if let i = settings.layout[side].firstIndex(where: { $0.id == id }) { edit(&settings.layout[side][i]); return }
    }
  }

  func removeWidget(_ id: UUID) {
    for side in Side.allCases {
      for s in settings.layout[side].indices { settings.layout[side][s].widgets.removeAll { $0.id == id } }
    }
  }

  func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<WidgetSpec, T>, default d: T) -> (get: () -> T, set: (T) -> Void) {
    (get: { [weak self] in self?.spec(id: id)?[keyPath: keyPath] ?? d },
     set: { [weak self] v in self?.update(id) { $0[keyPath: keyPath] = v } })
  }
}
