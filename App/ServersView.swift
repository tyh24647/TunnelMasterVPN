import SwiftUI

struct ServersView: View {
    @EnvironmentObject private var service: ServiceClient
    @State private var search = ""
    @State private var purpose = "All"
    private let purposes = ["All", "Streaming", "Transfers", "Security", "Privacy", "Stability", "Gaming"]
    var body: some View {
        List {
            Section {
                Picker("Best for", selection: $purpose) {
                    ForEach(purposes, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Notice(text: service.catalogIsLive ? "Metrics are provider measurements, not guarantees. A VPN does not make you anonymous or guarantee streaming access." : "Preview locations · no hosted VPN servers are online in this project yet. No fabricated performance ratings are shown.")
            }
            ForEach(service.servers.filter {
                (search.isEmpty || "\($0.country) \($0.city)".localizedCaseInsensitiveContains(search)) &&
                (purpose == "All" || $0.purposes.contains(purpose))
            }) { server in
                NavigationLink {
                    ServerDetailView(server: server)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(server.country).font(.headline)
                            Text(server.city).font(.subheadline).foregroundStyle(.secondary)
                            Text(server.online ? "Available" : "Not provisioned")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Pill(text: server.premium ? "Premium" : "Free", symbol: server.premium ? "sparkles" : "leaf")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Locations")
        .searchable(text: $search, prompt: "Country or city")
        .refreshable {
            await service.refresh()
        }
    }
}

struct ServerDetailView: View {
    @EnvironmentObject private var service: ServiceClient
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var vpn: VPNController
    let server: ServerLocation
    @State private var multiHop = false
    @State private var exitID = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                Text(server.country).font(.largeTitle.bold())
                Text(server.city).foregroundStyle(.secondary)
                Pill(text: server.premium ? "Premium capacity" : "Free capacity", symbol: "network")
            }
            Section("Measured performance") {
                LabeledContent("Latency", value: server.latencyMS.map { "\($0) ms" } ?? "Not measured")
                LabeledContent("Server load", value: server.loadPercent.map { "\($0)%" } ?? "Not measured")
                LabeledContent("Uptime", value: server.uptimePercent.map { "\($0)%" } ?? "Not measured")
                LabeledContent("Capacity", value: server.capacityMbps.map { "\($0) Mbps shared" } ?? "Not provisioned")
                if let date = server.measuredAt {
                    LabeledContent("Updated", value: date.formatted())
                }
            }
            Section("Security & privacy") {
                Text(server.protocols.map(\.rawValue).joined(separator: ", "))
                if let audit = server.auditURL, audit.scheme == "https" {
                    Link("Read published audit", destination: audit)
                } else {
                    Text("No independently verified audit provided.")
                }
                Notice(text: "Anonymity cannot be scored from a country or protocol alone. Provider logging, DNS, payment linkage, account identity and your browser also matter.")
            }
            Section("Double VPN") {
                Toggle("Use two server hops", isOn: $multiHop)
                    .disabled(server.multihopExits.isEmpty)
                if multiHop {
                    Picker("Exit location", selection: $exitID) {
                        Text("Select exit").tag("")
                        ForEach(service.servers.filter { server.multihopExits.contains($0.id) }) { exit in
                            Text("\(exit.country) · \(exit.city)").tag(exit.id)
                        }
                    }
                }
                Notice(text: "An entry server sees your connection while a separate exit reaches the destination. This can reduce exposure to one gateway, at the cost of latency and bandwidth. It does not guarantee anonymity. Compatible routes must be provisioned server-side; iOS does not stack two independent VPN apps.")
            }
            Section {
                Button("Connect to this location") {
                    busy = true
                    Task {
                        defer {
                            busy = false
                        }
                        do {
                            let provisioned = try await service.provision(server: server, exit: multiHop ? exitID : nil)
                            try Keychain.save(Data(provisioned.password.utf8), key: "\(provisioned.profile.id).password")
                            if let psk = provisioned.psk {
                                try Keychain.save(Data(psk.utf8), key: "\(provisioned.profile.id).psk")
                            }
                            try await vpn.connect(provisioned.profile, preferences: preferences.value)
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(!service.catalogIsLive || !server.online || busy || (multiHop && exitID.isEmpty))
                if !message.isEmpty {
                    Text(message).font(.footnote)
                }
                Notice(text: "Streaming availability depends on the service's policies and can change. Premium capacity is not a guaranteed speed on every network.")
            }
        }
        .navigationTitle(server.city)
    }
}
