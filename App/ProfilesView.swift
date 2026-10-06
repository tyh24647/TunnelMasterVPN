import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    var body: some View {
        List {
            Section {
                ForEach(preferences.value.profiles) { profile in
                    NavigationLink {
                        ProfileEditor(profile: profile)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.headline)
                            Text(profile.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let id = preferences.value.profiles[index].id
                        for suffix in ["password", "psk", "import"] {
                            Keychain.remove("\(id).\(suffix)")
                        }
                    }
                    preferences.value.profiles.remove(atOffsets: offsets)
                    preferences.save()
                }
                NavigationLink {
                    ProfileEditor(profile: VPNProfile())
                } label: {
                    Label("New configuration", systemImage: "plus.circle.fill")
                }
            }
            Section("Protocol support") {
                ForEach(TunnelProtocol.allCases) { kind in
                    DisclosureGroup(kind.rawValue) {
                        Text(kind.explanation).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Profiles")
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.dismiss) private var dismiss
    @State var profile: VPNProfile
    @State private var password = ""
    @State private var psk = ""
    @State private var bypass = ""
    @State private var imported = ""
    @State private var chooseFile = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Configuration") {
                TextField("Name", text: $profile.name)
                Picker("Protocol", selection: $profile.kind) {
                    ForEach(TunnelProtocol.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Notice(text: profile.kind.explanation)
            }
            if profile.kind == .dns {
                Section("Upstream DNS") {
                    TextField("Resolver IPv4", text: $profile.dnsUpstream)
                        .keyboardType(.decimalPad)
                    Notice(text: "Unblocked queries go to this resolver using UDP. Encrypted DNS in other apps may bypass this local filter.")
                }
            } else {
                Section("Server") {
                    TextField("Server hostname or IP", text: $profile.server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Remote ID / certificate hostname", text: $profile.remoteID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Local ID / group (optional)", text: $profile.localID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if profile.kind == .openVPN {
                        Picker("Transport", selection: $profile.transport) {
                            ForEach(Transport.allCases, id: \.self) { transport in
                                Text(transport.rawValue).tag(transport)
                            }
                        }
                    }
                }
                Section("Credentials · this device only") {
                    TextField("Username", text: $profile.username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    if profile.kind == .ipsec {
                        SecureField("Pre-shared secret", text: $psk)
                    }
                    Toggle("Disconnect on sleep", isOn: $profile.disconnectOnSleep)
                }
                if !profile.kind.available || profile.kind == .wireGuard {
                    Section("Imported configuration · Keychain only") {
                        Button("Import .conf / .ovpn / text") {
                            chooseFile = true
                        }
                        SecureField("Paste configuration", text: $imported)
                        Notice(text: "Private keys remain in Keychain. WireGuard requires the optional engine build; other unavailable protocols remain unavailable after import.")
                    }
                }
                Section("Domains to bypass") {
                    TextEditor(text: $bypass).frame(minHeight: 90)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Notice(text: "One hostname per line. Saved as profile intent. Native IKEv2/IPsec cannot enforce per-domain bypass; connection is blocked if this list is nonempty. DNS allow rules are separate and do not bypass an encrypted VPN.")
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Button("Save configuration") {
                save()
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Configuration")
        .onAppear {
            password = Keychain.read("\(profile.id).password").flatMap { String(data: $0, encoding: .utf8) } ?? ""
            psk = Keychain.read("\(profile.id).psk").flatMap { String(data: $0, encoding: .utf8) } ?? ""
            imported = Keychain.read("\(profile.id).import").flatMap { String(data: $0, encoding: .utf8) } ?? ""
            bypass = profile.bypassDomains.joined(separator: "\n")
        }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.data, .plainText]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                guard data.count <= 262_144, let text = String(data: data, encoding: .utf8) else {
                    throw ServiceError(message: "Use a UTF-8 configuration smaller than 256 KB.")
                }
                imported = text
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError(message: "Give this configuration a name.")
            }
            for (suffix, secret) in [("password", password), ("psk", psk), ("import", imported)] {
                if secret.isEmpty {
                    Keychain.remove("\(profile.id).\(suffix)")
                } else {
                    try Keychain.save(Data(secret.utf8), key: "\(profile.id).\(suffix)")
                }
            }
            profile.bypassDomains = bypass.split(whereSeparator: \.isNewline).map(String.init)
            if let index = preferences.value.profiles.firstIndex(where: { $0.id == profile.id }) {
                preferences.value.profiles[index] = profile
            } else {
                preferences.value.profiles.append(profile)
            }
            preferences.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
