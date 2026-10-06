import NetworkExtension
import Network

/// Routes only virtual DNS addresses into the extension. Ordinary app traffic stays on its normal route.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    #if TUNNELDOJO_WIREGUARD
    var wireGuard: WireGuardAdapter?
    #endif
    private let queue = DispatchQueue(label: "TunnelMasterVPN.DNS")
    private var preferences = Preferences()
    private var upstream = "1.1.1.1"
    private var running = false
    private var requests: [UUID: NWConnection] = [:]

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        #if TUNNELDOJO_WIREGUARD
        if let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
           config["engine"] as? String == "wireguard",
           let profileID = config["profileID"] as? String {
            startWireGuard(profileID: profileID, completion: completionHandler)
            return
        }
        #endif
        do {
            guard let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
                  let data = config["preferences"] as? Data,
                  let resolver = config["upstream"] as? String else {
                throw ServiceError(message: "DNS configuration is missing.")
            }
            preferences = try JSONDecoder().decode(Preferences.self, from: data)
            upstream = resolver
            try DNSMatcher.validate(preferences.rules)
            guard DNSMatcher.isIPv4(upstream), DNSMatcher.isIPv4(preferences.sinkIPv4) else {
                throw ServiceError(message: "Invalid DNS addresses.")
            }
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")
            let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.255.252"])
            ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "198.18.0.1", subnetMask: "255.255.255.255")]
            settings.ipv4Settings = ipv4
            let ipv6 = NEIPv6Settings(addresses: ["fd00:7475:6e6e::2"], networkPrefixLengths: [128])
            ipv6.includedRoutes = [NEIPv6Route(destinationAddress: "fd00:7475:6e6e::1", networkPrefixLength: 128)]
            settings.ipv6Settings = ipv6
            let dns = NEDNSSettings(servers: ["198.18.0.1", "fd00:7475:6e6e::1"])
            dns.matchDomains = [""]
            settings.dnsSettings = dns
            settings.mtu = 1280
            setTunnelNetworkSettings(settings) { error in
                self.queue.async {
                    self.running = error == nil
                    if self.running {
                        self.readPackets()
                    }
                    completionHandler(error)
                }
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        #if TUNNELDOJO_WIREGUARD
        if let wireGuard {
            wireGuard.stop { _ in
                completionHandler()
            }
            self.wireGuard = nil
            return
        }
        #endif
        queue.async {
            self.running = false
            for connection in self.requests.values {
                connection.cancel()
            }
            self.requests.removeAll()
            completionHandler()
        }
    }

    private func readPackets() {
        guard running else {
            return
        }
        packetFlow.readPackets { packets, _ in
            self.queue.async {
                for packet in packets {
                    self.process(packet)
                }
                self.readPackets()
            }
        }
    }

    private func process(_ packet: Data) {
        let bytes = [UInt8](packet)
        var offset = 0
        var count = 0
        let version = td_dns_extract(bytes, bytes.count, &offset, &count)
        guard version != 0 else {
            return
        }
        let query = Array(bytes[offset..<(offset + count)])
        var hostname = [CChar](repeating: 0, count: 256)
        let questionEnd = td_dns_question(query, query.count, &hostname, hostname.count)
        guard questionEnd > 0 else {
            return
        }
        do {
            if try DNSMatcher.blocked(String(cString: hostname), rules: preferences.rules) {
                respond(packet, dns: localAnswer(query, failure: false), version: version)
                return
            }
        } catch {
            respond(packet, dns: localAnswer(query, failure: true), version: version)
            return
        }
        guard requests.count < 128 else {
            respond(packet, dns: localAnswer(query, failure: true), version: version)
            return
        }
        let id = UUID()
        let connection = NWConnection(host: NWEndpoint.Host(upstream), port: 53, using: .udp)
        requests[id] = connection
        let finish: (Data?) -> Void = { data in
            guard self.requests.removeValue(forKey: id) != nil else {
                return
            }
            connection.cancel()
            var valid: Data?
            if let data, data.count >= Int(questionEnd), data.count <= 1232,
               data[0] == query[0], data[1] == query[1], data[2] & 0x80 != 0,
               data[2] & 0x02 == 0,
               Array(data[4..<6]) == Array(query[4..<6]),
               Array(data[12..<Int(questionEnd)]) == Array(query[12..<Int(questionEnd)]) {
                valid = data
            }
            self.respond(packet, dns: valid ?? self.localAnswer(query, failure: true), version: version)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(query), completion: .contentProcessed { error in
                    if error != nil {
                        finish(nil)
                    }
                })
                connection.receiveMessage { data, _, _, _ in
                    finish(data)
                }
            case .failed:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 4) {
            finish(nil)
        }
    }

    private func localAnswer(_ query: [UInt8], failure: Bool) -> Data {
        var output = [UInt8](repeating: 0, count: 1500)
        let count = td_dns_answer(query, query.count, preferences.sinkIPv4, failure ? 1 : 0, &output, output.count)
        return Data(output.prefix(Int(count)))
    }

    private func respond(_ packet: Data, dns: Data, version: Int32) {
        guard running else {
            return
        }
        let bytes = [UInt8](packet)
        let answer = [UInt8](dns)
        var output = [UInt8](repeating: 0, count: 1500)
        let count = td_dns_wrap(bytes, bytes.count, answer, answer.count, &output, output.count)
        guard count > 0 else {
            return
        }
        packetFlow.writePackets([Data(output.prefix(Int(count)))], withProtocols: [NSNumber(value: version == 4 ? AF_INET : AF_INET6)])
    }
}
