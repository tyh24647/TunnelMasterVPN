#if TUNNELDOJO_WIREGUARD
import Foundation

/// Wraps the upstream adapter. Engine logs are intentionally not persisted because they can contain endpoints.
extension PacketTunnelProvider {
    func startWireGuard(profileID: String, completion: @escaping (Error?) -> Void) {
        do {
            guard let data = Keychain.read("\(profileID).import"),
                  let text = String(data: data, encoding: .utf8) else {
                throw ServiceError(message: "WireGuard configuration is missing from this device's shared Keychain.")
            }
            let configuration = try TunnelConfiguration(fromWgQuickConfig: text, called: "TunnelMaster VPN")
            guard !configuration.peers.isEmpty else {
                throw ServiceError(message: "WireGuard needs at least one peer.")
            }
            wireGuard = WireGuardAdapter(with: self) { _, _ in }
            wireGuard?.start(tunnelConfiguration: configuration) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
}
#endif
