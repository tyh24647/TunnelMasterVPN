import SwiftUI
import NetworkExtension

struct RootView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @AppStorage("privacyAcknowledged.v1") private var acknowledged = false
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Connect", systemImage: "shield.lefthalf.filled")
            }
            NavigationStack {
                ServersView()
            }
            .tabItem {
                Label("Locations", systemImage: "globe")
            }
            NavigationStack {
                ProfilesView()
            }
            .tabItem {
                Label("Profiles", systemImage: "slider.horizontal.3")
            }
            NavigationStack {
                DNSRulesView()
            }
            .tabItem {
                Label("DNS Shield", systemImage: "hand.raised.fill")
            }
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .sheet(isPresented: Binding(get: { !acknowledged }, set: { _ in })) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 64))
                            .foregroundStyle(preferences.accent)
                        Text("Your connection.\nYour control.")
                            .font(.largeTitle.bold())
                        Text("This development build stores profiles and settings on your device. Passwords and private configuration text are stored in the device Keychain. Optional iCloud sync copies profile metadata and preferences, never credentials or logs.")
                        Text("Connection diagnostics stay in memory unless you export them. Browsing history and DNS hostnames are not logged. Account and purchase services, when configured, receive the information needed for authentication, device registration, billing verification and invitations. Your DNS resolver sees the queries forwarded to it.")
                        Text("The local DNS shield does not encrypt web traffic. Remote VPN protection is shown only when iOS reports a connected tunnel. Hosted locations remain unavailable until real servers are configured.")
                        Button("Continue") {
                            acknowledged = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(24)
                }
                .navigationTitle("Welcome to TunnelMaster VPN")
                .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled()
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var vpn: VPNController
    @EnvironmentObject private var service: ServiceClient
    @EnvironmentObject private var log: EventLog
    @State private var selected: UUID?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(preferences.accent.opacity(0.10))
                            .frame(width: 182, height: 182)
                        Circle().stroke(preferences.accent.opacity(0.25), lineWidth: 1)
                            .frame(width: 158, height: 158)
                        Image(systemName: vpn.status == .connected ? "checkmark.shield.fill" : "power")
                            .font(.system(size: 58, weight: .light))
                            .foregroundStyle(preferences.accent)
                    }
                    .accessibilityHidden(true)
                    Text(vpn.label).font(.title.bold())
                    Text(vpn.activeKind == .dns && vpn.status == .connected ? "Filtering DNS on this device" : "A little more privacy. A lot more control.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Pill(text: service.account?.premium == true ? "Premium" : "Free", symbol: "sparkles")
                        Pill(text: service.account == nil ? "Device only" : "Signed in", symbol: "person.crop.circle")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your connection").font(.headline)
                        if preferences.value.profiles.isEmpty {
                            NavigationLink("Create your first configuration") {
                                ProfileEditor(profile: VPNProfile())
                            }
                            Text("Bring your IKEv2/IPsec credentials, or set up the local DNS shield.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("Profile", selection: $selected) {
                                Text("Choose a profile").tag(Optional<UUID>.none)
                                ForEach(preferences.value.profiles) { profile in
                                    Text(profile.name).tag(Optional(profile.id))
                                }
                            }
                            Button(vpn.status == .connected ? "Disconnect" : "Connect") {
                                if vpn.status == .connected {
                                    vpn.disconnect()
                                } else if let profile = preferences.value.profiles.first(where: { $0.id == selected }) {
                                    Task {
                                        do {
                                            try await vpn.connect(profile, preferences: preferences.value)
                                        } catch {
                                            self.error = error.localizedDescription
                                            log.add("Connection could not start; check profile settings.", level: "Error")
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(vpn.busy || (selected == nil && vpn.status != .connected))
                        }
                        if vpn.status == .connecting || vpn.status == .reasserting {
                            Button("Cancel connection") {
                                vpn.disconnect()
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Go further with Premium", systemImage: "sparkles").font(.headline)
                        Text("Priority capacity, more locations, and eligible multi-hop routes once the hosted service is available.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink("Explore plans") {
                            PlansView()
                        }
                    }
                }
                Notice(text: service.catalogIsLive ? "Server recommendations use the provider's published measurements." : "Hosted network not provisioned. Location cards are labeled previews.")
                if !preferences.value.hideLogs {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Connection events", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("TunnelMaster VPN")
        .alert("Connection", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}
