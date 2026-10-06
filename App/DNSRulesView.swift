import SwiftUI

struct DNSRulesView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var vpn: VPNController
    @State private var draft = DNSRule()
    @State private var testHost = "ads.example.com"
    @State private var result = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label("DNS Shield", systemImage: "hand.raised.fill").font(.title2.bold())
                Notice(text: "A local DNS filter, not an encrypted VPN. Allow rules take precedence over block rules. Changes apply when you reconnect.")
                TextField("IPv4 answer for blocked hosts", text: preferences.binding(\.sinkIPv4))
                    .keyboardType(.decimalPad)
                Text("Default: 0.0.0.0. Blocked AAAA/HTTPS records return no data, preventing a matching hostname from escaping through IPv6 or address hints.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Start DNS shield") {
                    Task {
                        do {
                            var profile = preferences.value.profiles.first(where: { $0.kind == .dns }) ?? VPNProfile()
                            profile.kind = .dns
                            try await vpn.connect(profile, preferences: preferences.value)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .disabled(vpn.busy)
                Button("Stop current tunnel") {
                    vpn.disconnect()
                }
            }
            Section("Add a rule") {
                Picker("Match", selection: $draft.kind) {
                    ForEach(RuleKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                TextField("example.com, *.example.com, or regex", text: $draft.pattern, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Toggle("Allow this hostname", isOn: $draft.allow)
                Button("Add rule") {
                    do {
                        try DNSMatcher.validate(preferences.value.rules + [draft])
                        preferences.value.rules.append(draft)
                        preferences.save()
                        draft = DNSRule()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                Text(DNSMatcher.regexAvailable ? "PCRE2 interpreter available · full lookarounds, backreferences and recursion within resource limits." : "PCRE2 engine not bundled. Hostname and wildcard rules still work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your rules") {
                ForEach(preferences.value.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.pattern).font(.system(.body, design: .monospaced))
                            Text("\(rule.allow ? "Allow" : "Block") · \(rule.kind.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Enabled", isOn: Binding(get: {
                            preferences.value.rules.first(where: { $0.id == rule.id })?.enabled ?? false
                        }, set: { enabled in
                            if let index = preferences.value.rules.firstIndex(where: { $0.id == rule.id }) {
                                preferences.value.rules[index].enabled = enabled
                                preferences.save()
                            }
                        }))
                        .labelsHidden()
                    }
                }
                .onDelete { indices in
                    preferences.value.rules.remove(atOffsets: indices)
                    preferences.save()
                }
            }
            Section("Test a hostname") {
                TextField("Hostname", text: $testHost)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Evaluate rules") {
                    do {
                        result = try DNSMatcher.blocked(testHost, rules: preferences.value.rules) ? "Blocked" : "Allowed"
                    } catch {
                        result = error.localizedDescription
                    }
                }
                Text(result).font(.headline)
            }
        }
        .navigationTitle("DNS Shield")
        .alert("DNS rules", isPresented: Binding(get: { error != nil }, set: { _ in error = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}
