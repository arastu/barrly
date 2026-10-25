// swift-tools-version: 6.2
import PackageDescription
let package = Package(
  name: "GlassPanel",
  platforms: [.macOS(.v26)],
  targets: [.executableTarget(name: "GlassPanel", path: "Sources/GlassPanel", swiftSettings: [.swiftLanguageMode(.v6)])]
)
