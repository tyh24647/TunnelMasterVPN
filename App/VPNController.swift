import Foundation
import Combine
import NetworkExtension

/// One operating-system VPN slot, with connection status sourced only from NetworkExtension.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var activeKind: TunnelProtocol?
    @Published private(set) var busy = false
    private var current: NEVPNManager?
    private var observer: NSObjectProtocol?
    let log: EventLog

    init(log: EventLog) {
        self.log = log
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        Task {
            await restore()
        }
    }

    var label: String {
        switch status {
        case .connected:
            return activeKind == .dns ? "DNS filter active" : "VPN connected"
        case .connecting, .reasserting:
            return "Connecting…"
        case .disconnecting:
            return "Disconnecting…"
        default:
            return "Disconnected"
        }
    }

    private func refreshStatus() {
        status = current?.connection.status ?? .disconnected
        log.add("Tunnel state: \(label)")
    }

    private func restore() async {
        let native = NEVPNManager.shared()
        try? await native.loadFromPreferences()
        let tunnels = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        if let active = tunnels.first(where: { $0.connection.status != .disconnected && $0.connection.status != .invalid }) {
            current = active
            activeKind = (active.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["engine"] as? String == "wireguard" ? .wireGuard : .dns
        } else {
            current = native
            activeKind = native.protocolConfiguration is NEVPNProtocolIKEv2 ? .ikev2 : .ipsec
        }
        refreshStatus()
    }

    func connect(_ profile: VPNProfile, preferences: Preferences) async throws {
        guard !busy else {
            return
        }
        log.add("Validating configuration and engine availability.", level: "Debug")
        busy = true
        defer {
            busy = false
        }
        guard status == .disconnected || status == .invalid else {
            throw ServiceError(message: "Disconnect the current tunnel before starting another one.")
        }
        guard profile.kind.available else {
            throw ServiceError(message: profile.kind.explanation)
        }
        guard profile.bypassDomains.isEmpty || profile.kind == .dns else {
            throw ServiceError(message: "Native IKEv2/IPsec cannot apply this app's per-domain bypass rules. Remove the bypass list or use a future routing engine that supports it. Nothing was connected.")
        }
        if profile.kind == .wireGuard {
            try await startWireGuard(profile)
        } else if profile.kind == .dns {
            try await startDNS(profile, preferences: preferences)
        } else {
            try await startNative(profile)
        }
        activeKind = profile.kind
        refreshStatus()
    }

    private func startNative(_ profile: VPNProfile) async throws {
        guard !profile.server.trimmingCharacters(in: .whitespaces).isEmpty,
              !profile.username.isEmpty,
              let password = Keychain.read("\(profile.id).password") else {
            throw ServiceError(message: "Enter the server, username and password on this device.")
        }
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        let configuration: NEVPNProtocolIPSec
        if profile.kind == .ikev2 {
            guard !profile.remoteID.isEmpty else {
                throw ServiceError(message: "Enter the server certificate's remote identifier.")
            }
            let ike = NEVPNProtocolIKEv2()
            ike.authenticationMethod = .none
            ike.useExtendedAuthentication = true
            ike.remoteIdentifier = profile.remoteID
            ike.localIdentifier = profile.localID.isEmpty ? nil : profile.localID
            ike.deadPeerDetectionRate = .medium
            configuration = ike
        } else {
            guard let secret = Keychain.read("\(profile.id).psk") else {
                throw ServiceError(message: "Enter the IPsec pre-shared secret on this device.")
            }
            let ipsec = NEVPNProtocolIPSec()
            ipsec.authenticationMethod = .sharedSecret
            ipsec.useExtendedAuthentication = true
            ipsec.sharedSecretReference = try Keychain.save(secret, key: "\(profile.id).psk")
            ipsec.localIdentifier = profile.localID.isEmpty ? nil : profile.localID
            configuration = ipsec
        }
        configuration.serverAddress = profile.server
        configuration.username = profile.username
        configuration.passwordReference = try Keychain.save(password, key: "\(profile.id).password")
        configuration.disconnectOnSleep = profile.disconnectOnSleep
        configuration.includeAllNetworks = true
        configuration.excludeLocalNetworks = false
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "TunnelMaster VPN • \(profile.name)"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        log.add("Saving NetworkExtension configuration.", level: "Debug")
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        current = manager
        log.add("Starting native VPN; system certificate validation enabled.")
        try manager.connection.startVPNTunnel()
    }

    private func startDNS(_ profile: VPNProfile, preferences: Preferences) async throws {
        try DNSMatcher.validate(preferences.rules)
        guard DNSMatcher.isIPv4(preferences.sinkIPv4), DNSMatcher.isIPv4(profile.dnsUpstream),
              profile.dnsUpstream != "0.0.0.0", profile.dnsUpstream != "198.18.0.1" else {
            throw ServiceError(message: "Enter a valid IPv4 sink and reachable IPv4 upstream DNS resolver.")
        }
        let bundle = Bundle.main.bundleIdentifier! + ".PacketTunnel"
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundle
        }) ?? NETunnelProviderManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = bundle
        configuration.serverAddress = "Local DNS filter"
        configuration.providerConfiguration = [
            "preferences": try JSONEncoder().encode(preferences),
            "upstream": profile.dnsUpstream
        ]
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "TunnelMaster VPN DNS • local filtering only"
        manager.isEnabled = true
        log.add("Saving NetworkExtension configuration.", level: "Debug")
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        current = manager
        log.add("Starting local DNS filter. Web traffic is not encrypted by this mode.", level: "Warning")
        try manager.connection.startVPNTunnel()
    }

    private func startWireGuard(_ profile: VPNProfile) async throws {
        guard Keychain.read("\(profile.id).import") != nil else {
            throw ServiceError(message: "Import the WireGuard .conf file first.")
        }
        let bundle = Bundle.main.bundleIdentifier! + ".PacketTunnel"
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundle
        }) ?? NETunnelProviderManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = bundle
        configuration.serverAddress = profile.server.isEmpty ? "WireGuard" : profile.server
        configuration.providerConfiguration = ["engine": "wireguard", "profileID": profile.id.uuidString]
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "TunnelMaster VPN • \(profile.name)"
        manager.isEnabled = true
        log.add("Saving NetworkExtension configuration.", level: "Debug")
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        current = manager
        log.add("Starting WireGuard adapter.")
        try manager.connection.startVPNTunnel()
    }

    func disconnect() {
        current?.connection.stopVPNTunnel()
        log.add("Disconnect requested.")
    }
}
