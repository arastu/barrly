import Foundation
import os

/// Raw client for the AeroSpace Unix socket (protocol v1): 4-byte version handshake, then
/// UInt32-length-prefixed JSON frames. One connection per instance; `request` is synchronous
/// and must be called off the main thread. A `subscribe` request turns the connection into a stream.
final class AerospaceClient: @unchecked Sendable {
  struct Reply: Decodable, Sendable { var exitCode: Int32; var stdout: String; var stderr: String }
  enum ClientError: Error { case connect(Int32), eof, badVersion(UInt32), encode }

  static var socketPath: String { "/tmp/bobko.aerospace-\(NSUserName()).sock" }
  private var fd: Int32 = -1
  private let lock = NSLock()

  func connect() throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.connect(errno) }
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutablePointer(to: &addr.sun_path) { sp in
      let dst = UnsafeMutableRawPointer(sp).assumingMemoryBound(to: CChar.self)
      Self.socketPath.withCString { _ = strlcpy(dst, $0, capacity) }
    }
    let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard rc == 0 else { let e = errno; close(fd); throw ClientError.connect(e) }
    var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    self.fd = fd
    var ver: UInt32 = 1
    try writeAll(Data(bytes: &ver, count: 4))
    let server = try readExact(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    guard server == 1 else { throw ClientError.badVersion(server) }
  }

  func disconnect() { lock.lock(); if fd >= 0 { close(fd); fd = -1 }; lock.unlock() }
  var isConnected: Bool { fd >= 0 }

  /// Send a command and wait for its reply.
  func request(_ args: [String], stdin: String = "") throws -> Reply {
    lock.lock(); defer { lock.unlock() }
    try send(args, stdin: stdin)
    return try readFrame()
  }

  /// Send a command without waiting (used to start a subscribe stream).
  func send(_ args: [String], stdin: String = "") throws {
    let body: [String: Any] = ["args": args, "stdin": stdin]
    guard let json = try? JSONSerialization.data(withJSONObject: body) else { throw ClientError.encode }
    var len = UInt32(json.count)
    try writeAll(Data(bytes: &len, count: 4)); try writeAll(json)
  }

  /// Blocking read of the next frame (stream events or replies).
  func readFrame() throws -> Reply {
    let n = Int(try readExact(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    let data = try readExact(n)
    return try JSONDecoder().decode(Reply.self, from: data)
  }

  /// Blocking read of the next raw JSON frame as a dictionary (subscribe events are not Reply-shaped).
  func readJSON() throws -> [String: Any] {
    let n = Int(try readExact(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    let data = try readExact(n)
    return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private func writeAll(_ d: Data) throws {
    try d.withUnsafeBytes { buf in
      var off = 0
      while off < d.count {
        let n = Darwin.write(fd, buf.baseAddress! + off, d.count - off)
        guard n > 0 else { throw ClientError.eof }
        off += n
      }
    }
  }

  private func readExact(_ n: Int) throws -> Data {
    var d = Data(count: n); var off = 0
    try d.withUnsafeMutableBytes { buf in
      while off < n {
        let r = Darwin.read(fd, buf.baseAddress! + off, n - off)
        guard r > 0 else { throw ClientError.eof }
        off += r
      }
    }
    return d
  }
}
