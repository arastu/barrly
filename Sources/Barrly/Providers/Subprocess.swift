import Foundation

/// Runs a command line tool once and collects its output. Used for the `claude` and `rex` CLIs.
enum Subprocess {
  struct Result: Sendable {
    var ok: Bool
    var stdout: Data
    var stderr: String
    /// The last line of stderr, for a notice.
    var lastErrorLine: String { stderr.split(separator: "\n").last.map(String.init) ?? "failed" }
    func json() -> Any? { ok ? try? JSONSerialization.jsonObject(with: stdout) : nil }
  }

  /// Barrly is launched by launchd with a minimal PATH; tools the CLIs spawn (node, gh) may need more.
  nonisolated static let environment: [String: String] = {
    var env = ProcessInfo.processInfo.environment
    let extra = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
    return env
  }()

  /// Runs `executable` (an absolute path) with `args`, killing it after `timeout` seconds.
  nonisolated static func run(_ executable: String, _ args: [String], timeout: TimeInterval = 8,
                              environment: [String: String]? = nil) async -> Result {
    await withCheckedContinuation { cont in
      DispatchQueue.global(qos: .userInitiated).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.environment = environment ?? Self.environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
          cont.resume(returning: Result(ok: false, stdout: Data(), stderr: error.localizedDescription)); return
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // stderr is drained on its own queue so a chatty tool cannot block on a full pipe.
        let errQueue = DispatchQueue(label: "dev.barrly.subprocess.stderr")
        nonisolated(unsafe) var errData = Data()
        errQueue.async { errData = err.fileHandleForReading.readDataToEndOfFile() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        errQueue.sync {}
        killer.cancel()
        cont.resume(returning: Result(ok: p.terminationStatus == 0, stdout: outData, stderr: String(decoding: errData, as: UTF8.self)))
      }
    }
  }

  /// The command line of a running process (KERN_PROCARGS2), or empty when it is gone or not ours.
  nonisolated static func arguments(ofPid pid: Int32) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
    let argc = Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
    var i = 4
    while i < size, buf[i] != 0 { i += 1 }   // the executable path
    while i < size, buf[i] == 0 { i += 1 }   // padding
    var args: [String] = []
    while args.count < argc, i < size {
      let start = i
      while i < size, buf[i] != 0 { i += 1 }
      args.append(String(decoding: buf[start..<i], as: UTF8.self))
      i += 1
    }
    return args
  }
}
