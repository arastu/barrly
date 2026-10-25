// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Barrly",
  platforms: [.macOS(.v26)],
  targets: [
    .executableTarget(
      name: "Barrly",
      path: "Sources/Barrly",
      resources: [.copy("Resources")],
      swiftSettings: [.swiftLanguageMode(.v6)],
      linkerSettings: [
        .linkedFramework("AppKit"), .linkedFramework("SwiftUI"), .linkedFramework("IOKit"),
        .linkedFramework("CoreWLAN"), .linkedFramework("SystemConfiguration"), .linkedFramework("EventKit"),
        .linkedFramework("Carbon"), .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "BarrlyTests",
      dependencies: ["Barrly"],
      path: "Tests/BarrlyTests",
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        // Command Line Tools ship the swift-testing macro plugin but do not put it on the search path.
        .unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"]),
      ]
    ),
  ]
)
