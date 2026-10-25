import Foundation
import Testing
@testable import Barrly

@Suite struct AerospaceTests {
  @Test func decodesWindows() throws {
    let url = Bundle.module.url(forResource: "list-windows", withExtension: "json", subdirectory: "Fixtures/aerospace")!
    let windows = try JSONDecoder().decode([AeroWindow].self, from: Data(contentsOf: url))
    #expect(windows.count == 4)
    #expect(windows[2].bundleId == "com.mitchellh.ghostty")
    let ws = AeroWorkspace(id: "2", isFocused: true, windows: windows.filter { $0.workspace == "2" })
    #expect(ws.bundleIds == ["com.mitchellh.ghostty"]) // de-duplicated
  }
}
