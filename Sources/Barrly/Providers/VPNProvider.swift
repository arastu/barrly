import Foundation
import Network
import Observation
import SystemConfiguration

struct VPNConnection: Hashable, Sendable, Identifiable {
  var id: String          // service id, or interface name for unregistered tunnels
  var name: String        // user-visible service name ("Office", "touhids_laptop")
  var kind: String        // VPN sub-type ("com.wireguard.macos") or interface name
}

struct VPNState: Hashable, Sendable {
  var connections: [VPNConnection] = []
  var active: Bool { !connections.isEmpty }
}

/// Which VPNs are up. Two sources, both native and push-driven:
/// 1. Every VPN / IPSec / L2TP service of the current network set, watched through
///    `SCNetworkConnection` status callbacks (the same thing `scutil --nc list` reports; this is
///    how Network Extension VPNs such as WireGuard, Cisco, OpenVPN and NordVPN show up).
/// 2. A fallback for tunnels that never registered a service: a `utun`/`ipsec`/`ppp` interface
///    that carries an IPv4 address, re-checked whenever `NWPathMonitor` sees the path change.
@MainActor @Observable
final class VPNProvider {
  private(set) var state = VPNState()
  @ObservationIgnored private var services: [String: Service] = [:]
  @ObservationIgnored private var store: SCDynamicStore? = nil
  @ObservationIgnored private var storeSource: CFRunLoopSource? = nil
  @ObservationIgnored private var pathMonitor: NWPathMonitor? = nil
  @ObservationIgnored private var token: Scheduler.Token? = nil

  private struct Service { var name: String; var subType: String; var connection: SCNetworkConnection }

  private static let statusCallback: SCNetworkConnectionCallBack = { _, _, info in
    guard let info else { return }
    let me = Unmanaged<VPNProvider>.fromOpaque(info).takeUnretainedValue()
    Task { @MainActor in me.refresh() }
  }

  init(scheduler: Scheduler) {
    // Service list changes (a VPN app installs or removes its configuration).
    var ctx = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
    store = SCDynamicStoreCreate(nil, "dev.barrly.vpn" as CFString, { _, _, info in
      guard let info else { return }
      let me = Unmanaged<VPNProvider>.fromOpaque(info).takeUnretainedValue()
      Task { @MainActor in me.reloadServices() }
    }, &ctx)
    if let store {
      SCDynamicStoreSetNotificationKeys(store, nil, ["Setup:/Network/Service/.*/Interface" as CFString, "Setup:/Network/Global/IPv4" as CFString] as CFArray)
      storeSource = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
      if let storeSource { CFRunLoopAddSource(CFRunLoopGetMain(), storeSource, .defaultMode) }
    }
    // Tunnel interfaces coming and going (fallback source).
    let monitor = NWPathMonitor()
    let bits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    monitor.pathUpdateHandler = { _ in
      guard let ptr = UnsafeMutableRawPointer(bitPattern: bits) else { return }
      let me = Unmanaged<VPNProvider>.fromOpaque(ptr).takeUnretainedValue()
      Task { @MainActor in me.refresh() }
    }
    monitor.start(queue: .main)
    pathMonitor = monitor
    token = scheduler.schedule(every: 30) { [weak self] in self?.refresh() }
    reloadServices()
  }

  /// Enumerate VPN-like services of the current set and subscribe to their status.
  func reloadServices() {
    var next: [String: Service] = [:]
    if let prefs = SCPreferencesCreate(nil, "dev.barrly.vpn" as CFString, nil),
       let set = SCNetworkSetCopyCurrent(prefs),
       let list = SCNetworkSetCopyServices(set) as? [SCNetworkService] {
      for s in list where SCNetworkServiceGetEnabled(s) {
        guard let iface = SCNetworkServiceGetInterface(s), let id = SCNetworkServiceGetServiceID(s) as String? else { continue }
        let type = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""
        let sub = Self.subType(of: iface)
        let isVPN = type == "VPN" || type == (kSCNetworkInterfaceTypeIPSec as String)
          || (type == (kSCNetworkInterfaceTypePPP as String) && Self.underlyingType(of: iface) == (kSCNetworkInterfaceTypeL2TP as String))
        guard isVPN else { continue }
        let name = SCNetworkServiceGetName(s) as String? ?? "VPN"
        if let existing = services[id] { next[id] = Service(name: name, subType: sub, connection: existing.connection); continue }
        var cctx = SCNetworkConnectionContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let conn = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, Self.statusCallback, &cctx) else { continue }
        SCNetworkConnectionScheduleWithRunLoop(conn, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        next[id] = Service(name: name, subType: sub, connection: conn)
      }
    }
    for (id, old) in services where next[id] == nil {
      SCNetworkConnectionUnscheduleFromRunLoop(old.connection, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
    services = next
    refresh()
  }

  func refresh() {
    var out: [VPNConnection] = []
    for (id, s) in services where SCNetworkConnectionGetStatus(s.connection) == .connected {
      out.append(VPNConnection(id: id, name: s.name, kind: s.subType))
    }
    if out.isEmpty {
      for ifname in Self.tunnelInterfacesWithAddress() { out.append(VPNConnection(id: ifname, name: "VPN", kind: ifname)) }
    }
    out.sort { $0.name < $1.name }
    let s = VPNState(connections: out)
    if s != state { state = s }
  }

  private static func subType(of iface: SCNetworkInterface) -> String {
    (SCNetworkInterfaceGetConfiguration(iface) as? [String: Any])?["SubType"] as? String
      ?? (SCNetworkInterfaceGetBSDName(iface) as String?) ?? ""
  }
  private static func underlyingType(of iface: SCNetworkInterface) -> String? {
    SCNetworkInterfaceGetInterface(iface).flatMap { SCNetworkInterfaceGetInterfaceType($0) as String? }
  }

  /// Point-to-point tunnel interfaces that carry an IPv4 address. macOS keeps a few idle
  /// `utun` interfaces for its own services; those only have link-local IPv6, so they are skipped.
  static func tunnelInterfacesWithAddress() -> [String] {
    var head: UnsafeMutablePointer<ifaddrs>? = nil
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var names = Set<String>()
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = p {
      defer { p = cur.pointee.ifa_next }
      guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
            (Int32(cur.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
      let name = String(cString: cur.pointee.ifa_name)
      if ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains(where: { name.hasPrefix($0) }) { names.insert(name) }
    }
    return names.sorted()
  }
}
