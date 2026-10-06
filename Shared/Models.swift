import Foundation

/// TCP/UDP are transports, separate from the encrypted tunnel protocol.
enum TunnelProtocol: String, Codable, CaseIterable, Identifiable {
    case ikev2 = "IKEv2 / IPsec"
    case ipsec = "IPsec (IKEv1)"
    case wireGuard = "WireGuard"
    case openVPN = "OpenVPN"
    case sstp = "SSTP"
    case pptp = "PPTP"
    case localDeveloper = "Local developer / JIT"
    case dns = "AdBlock DNS"

    var id: String {
        rawValue
    }

    var available: Bool {
        #if TUNNELDOJO_WIREGUARD
        return self == .ikev2 || self == .ipsec || self == .dns || self == .wireGuard
        #else
        return self == .ikev2 || self == .ipsec || self == .dns
        #endif
    }

    var explanation: String {
        switch self {
        case .ikev2:
            return "Native encrypted VPN. Configure a trusted server, certificate identity and EAP username/password."
        case .ipsec:
            return "Native legacy IPsec with a pre-shared secret and extended authentication. Prefer IKEv2 on new deployments."
        case .wireGuard:
            return "Uses UDP. Import a complete .conf file. The included WireGuard adapter requires the optional WireGuard build and Go bridge; see the build guide."
        case .openVPN:
            return "Supports UDP or TCP. Requires an OpenVPN core, licensing review and packet-tunnel adapter; not linked in this build."
        case .sstp:
            return "TLS over TCP, usually port 443. A third-party SSTP engine is required; not linked in this build."
        case .pptp:
            return "Not supported by native modern iOS VPN APIs and obsolete for security. Migrate the server to IKEv2 or WireGuard."
        case .localDeveloper:
            return "StosVPN / LocalDevVPN are developer tools, not standard VPN protocols. A local tunnel does not grant JIT permission. No compatible engine is included."
        case .dns:
            return "Local DNS filtering only: no remote exit country and no traffic encryption. Uses the VPN slot and cannot run alongside a separate VPN in this app."
        }
    }
}

enum Transport: String, Codable, CaseIterable {
    case automatic = "Automatic"
    case udp = "UDP"
    case tcp = "TCP"
}

struct VPNProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "New configuration"
    var kind: TunnelProtocol = .ikev2
    var server = ""
    var remoteID = ""
    var localID = ""
    var username = ""
    var transport: Transport = .automatic
    var dnsUpstream = "1.1.1.1"
    var bypassDomains: [String] = []
    var disconnectOnSleep = false
    // Passwords, PSKs and imported private keys are Keychain-only, never Codable.
}

enum RuleKind: String, Codable, CaseIterable {
    case hostname = "Hostname"
    case wildcard = "Wildcard"
    case regex = "PCRE2 regex"
}

struct DNSRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var pattern = ""
    var kind: RuleKind = .hostname
    var allow = false
    var enabled = true
}

struct Preferences: Codable, Equatable {
    var theme = "Auto"
    var accentRed = 0.62
    var accentGreen = 0.35
    var accentBlue = 0.98
    var cloudSync = false
    var hideLogs = false
    var verbose = false
    var logFilter = "All"
    var sinkIPv4 = "0.0.0.0"
    var rules: [DNSRule] = []
    var profiles: [VPNProfile] = []
    var modified = Date()
}

struct ServerLocation: Codable, Identifiable {
    var id: String
    var country: String
    var city: String
    var premium: Bool
    var protocols: [TunnelProtocol]
    var purposes: [String]
    var online: Bool
    var latencyMS: Int?
    var loadPercent: Int?
    var uptimePercent: Double?
    var capacityMbps: Int?
    var auditURL: URL?
    var multihopExits: [String]
    var measuredAt: Date?

    static let preview: [ServerLocation] = [
        ("US", "United States", "New York", false),
        ("DE", "Germany", "Frankfurt", false),
        ("JP", "Japan", "Tokyo", false),
        ("GB", "United Kingdom", "London", true),
        ("CH", "Switzerland", "Zurich", true),
        ("SG", "Singapore", "Singapore", true),
        ("CA", "Canada", "Toronto", true),
        ("AU", "Australia", "Sydney", true)
    ].map { code, country, city, premium in
        ServerLocation(id: "preview-\(code)", country: country, city: city,
                       premium: premium, protocols: [.ikev2, .wireGuard], purposes: [],
                       online: false, multihopExits: [])
    }
}

struct Account: Codable {
    var id: String
    var username: String
    var referralCode: String
    var family: Bool
    var deviceCount: Int
    var deviceLimit: Int?
    var premium: Bool
}

struct Session: Codable {
    var token: String
    var account: Account
}

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
