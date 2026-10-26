import CoreWLAN
import Foundation
import Observation
import SystemConfiguration

struct NetworkState: Hashable, Sendable {
  var interface: String?
  var ipv4: String?
  var isWifi: Bool
  var connected: Bool { ipv4 != nil }
}

/// Primary IPv4 via SCDynamicStore change notifications. No Location permission needed
/// (we never read the SSID).
@MainActor @Observable
final class NetworkProvider {
  private(set) var state = NetworkState(interface: nil, ipv4: nil, isWifi: false)
  @ObservationIgnored private var store: SCDynamicStore? = nil
  @ObservationIgnored private var source: CFRunLoopSource? = nil

  init() {
    var ctx = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
    store = SCDynamicStoreCreate(nil, "dev.barrly.network" as CFString, { _, _, info in
      guard let info else { return }
      let me = Unmanaged<NetworkProvider>.fromOpaque(info).takeUnretainedValue()
      Task { @MainActor in me.refresh() }
    }, &ctx)
    if let store {
      SCDynamicStoreSetNotificationKeys(store, ["State:/Network/Global/IPv4" as CFString] as CFArray,
                                        ["State:/Network/Interface/.*/IPv4" as CFString] as CFArray)
      source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
      if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }
    refresh()
  }


  static func isTunnel(_ name: String) -> Bool { ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { name.hasPrefix($0) } }

  func refresh() {
    guard let store else { return }
    var ifname: String? = nil, ip: String? = nil
    if let g = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
       let primary = g["PrimaryInterface"] as? String {
      ifname = primary
      if let v = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(primary)/IPv4" as CFString) as? [String: Any] {
        ip = (v["Addresses"] as? [String])?.first
      }
    }
    let wifiName = CWWiFiClient.shared().interface()?.interfaceName
    // A VPN tunnel becoming the primary route should not turn the Wi-Fi widget into a globe:
    // keep reporting the Wi-Fi interface and its LAN address while it is up.
    if let p = ifname, let wifiName, Self.isTunnel(p),
       let v = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(wifiName)/IPv4" as CFString) as? [String: Any],
       let addr = (v["Addresses"] as? [String])?.first {
      ifname = wifiName; ip = addr
    }
    let s = NetworkState(interface: ifname, ipv4: ip, isWifi: ifname != nil && ifname == wifiName)
    if s != state { state = s }
  }
}
