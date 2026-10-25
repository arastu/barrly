// Spike 4: talk to AeroSpace over its Unix socket (no CLI fork).
// Protocol (v0.21+): both sides send a 4-byte version (little-endian UInt32 = 1),
// then UInt32-length-prefixed UTF-8 JSON frames.
setvbuf(stdout, nil, _IONBF, 0)
import Foundation

let path = "/tmp/bobko.aerospace-\(NSUserName()).sock"
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &addr.sun_path) { sp in
  let dst = UnsafeMutableRawPointer(sp).assumingMemoryBound(to: CChar.self)
  path.withCString { _ = strcpy(dst, $0) }
}
let len = socklen_t(MemoryLayout<sockaddr_un>.size)
guard withUnsafePointer(to: &addr, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } }) == 0 else { print("connect failed", errno); exit(1) }

func writeAll(_ d: Data) { d.withUnsafeBytes { var o = 0; while o < d.count { let n = write(fd, $0.baseAddress! + o, d.count - o); precondition(n > 0); o += n } } }
func readExact(_ n: Int) -> Data { var d = Data(count: n); var o = 0; d.withUnsafeMutableBytes { while o < n { let r = read(fd, $0.baseAddress! + o, n - o); precondition(r > 0, "eof"); o += r } }; return d }
func u32(_ d: Data) -> UInt32 { d.withUnsafeBytes { $0.load(as: UInt32.self) } }
func send(_ obj: [String: Any]) { let j = try! JSONSerialization.data(withJSONObject: obj); var l = UInt32(j.count); writeAll(Data(bytes: &l, count: 4)); writeAll(j) }
func recv() -> [String: Any] { let n = Int(u32(readExact(4))); return try! JSONSerialization.jsonObject(with: readExact(n)) as! [String: Any] }

var ver: UInt32 = 1
writeAll(Data(bytes: &ver, count: 4))
let serverVer = u32(readExact(4)); print("server protocol version:", serverVer)

let t0 = Date()
send(["args": ["list-workspaces", "--all", "--json"], "stdin": ""])
let r1 = recv(); print("list-workspaces exit", r1["exitCode"] ?? "?", "in", Int(Date().timeIntervalSince(t0)*1000), "ms, bytes:", (r1["stdout"] as? String)?.count ?? 0)
send(["args": ["list-windows", "--all", "--json", "--format", "%{window-id} %{app-bundle-id} %{app-name} %{workspace}"], "stdin": ""])
let r2 = recv(); print("list-windows exit", r2["exitCode"] ?? "?", String((r2["stdout"] as? String ?? "").prefix(300)))

let mode = CommandLine.arguments.dropFirst().first ?? "once"
if mode == "subscribe" {
  send(["args": ["subscribe", "focused-workspace-changed", "focus-changed", "window-detected"], "stdin": ""])
  print("subscribed; switch workspaces now (10 s)…")
  let deadline = Date().addingTimeInterval(10)
  while Date() < deadline {
    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    if poll(&pfd, 1, 500) > 0 { let r = recv(); print("event @\(Date()):", String(describing: r).prefix(400)) }
  }
}
close(fd)
