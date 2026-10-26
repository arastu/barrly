import Foundation

/// Every widget Barrly ships. There is no plugin system: this enum is the catalogue.
enum WidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case appleMenu, workspaces, frontApp, nowPlaying
  case cpu, ram, wifi, battery, jalaliDate, clock, inputSource, meeting
  case spacer

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appleMenu: "Apple menu"
    case .workspaces: "Workspaces"
    case .frontApp: "Front app"
    case .nowPlaying: "Now playing"
    case .cpu: "CPU"
    case .ram: "Memory"
    case .wifi: "Wi‑Fi"
    case .battery: "Battery"
    case .jalaliDate: "Jalali date"
    case .clock: "Clock"
    case .inputSource: "Input source"
    case .meeting: "Meeting"
    case .spacer: "Spacer"
    }
  }

  var symbol: String {
    switch self {
    case .appleMenu: "apple.logo"
    case .workspaces: "square.grid.3x3"
    case .frontApp: "macwindow"
    case .nowPlaying: "music.note"
    case .cpu: "cpu"
    case .ram: "memorychip"
    case .wifi: "wifi"
    case .battery: "battery.75percent"
    case .jalaliDate: "calendar"
    case .clock: "clock"
    case .inputSource: "keyboard"
    case .meeting: "video.fill"
    case .spacer: "arrow.left.and.right"
    }
  }

  /// Default icon colour when "Colourful icons" is on.
  var defaultTint: AccentToken? {
    switch self {
    case .cpu: .blue
    case .ram: .mauve
    case .wifi: .sapphire
    case .battery: .green
    case .jalaliDate: .peach
    case .clock: .red
    case .inputSource: .teal
    case .meeting: .lavender
    case .nowPlaying: .pink
    case .appleMenu, .workspaces, .frontApp, .spacer: nil
    }
  }

  /// Widgets that make sense to add more than once (spacers); everything else is singleton.
  var allowsDuplicates: Bool { self == .spacer }
}
