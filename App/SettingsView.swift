import SwiftUI
import MessageUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var service: ServiceClient
    var body: some View {
        Form {
            Section("Make it yours") {
                Picker("Appearance", selection: preferences.binding(\.theme)) {
                    ForEach(["Auto", "Light", "Dark"], id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                ColorPicker("Highlight color", selection: Binding(get: { preferences.accent }, set: { color in
                    var r: CGFloat = 0
                    var g: CGFloat = 0
                    var b: CGFloat = 0
                    var a: CGFloat = 0
                    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                    preferences.value.accentRed = Double(r)
                    preferences.value.accentGreen = Double(g)
                    preferences.value.accentBlue = Double(b)
                    preferences.save()
                }), supportsOpacity: false)
            }
            Section("Account & devices") {
                NavigationLink(service.account?.username ?? "Sign in or use anonymously") {
                    AccountView()
                }
                Toggle("Sync settings with iCloud", isOn: preferences.binding(\.cloudSync))
                    .disabled(service.account == nil)
                Notice(text: preferences.syncMessage)
                Notice(text: "Anonymous mode keeps preferences on this device. An account supports three registered devices; family memberships have no app-imposed device cap. iCloud sync uses the same Apple Account and requires the app on each device. Credentials must be entered per device.")
                NavigationLink("Premium & family plans") {
                    PlansView()
                }
            }
            Section("Diagnostics") {
                Toggle("Hide logs view", isOn: preferences.binding(\.hideLogs))
                Toggle("Verbose operational events", isOn: preferences.binding(\.verbose))
                if !preferences.value.hideLogs {
                    NavigationLink("View event log") {
                        LogsView()
                    }
                }
            }
            Section("Help") {
                NavigationLink("Protocol setup & troubleshooting") {
                    FAQView()
                }
                NavigationLink("Privacy & data use") {
                    PrivacyView()
                }
                Link("Developer website", destination: URL(string: "https://tylero056.com")!)
                Link("Developer GitHub", destination: URL(string: "https://github.com/tyh24647")!)
                Text("TunnelMaster VPN · Development build 1.0\nPCRE2: BSD license, included in source distribution. Native VPN: Apple NetworkExtension. No analytics or advertising SDKs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

struct AccountView: View {
    @EnvironmentObject private var service: ServiceClient
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var confirmation = ""
    @State private var message = ""
    @State private var busy = false
    @State private var confirmDelete = false
    private let providers = ["Apple", "Microsoft", "Discord", "GitHub", "Facebook", "Google"]
    var body: some View {
        Form {
            if let account = service.account {
                Section("Your account") {
                    LabeledContent("Username", value: account.username)
                    LabeledContent("Devices", value: "\(account.deviceCount) / \(account.deviceLimit.map(String.init) ?? "Unlimited")")
                    LabeledContent("Referral code", value: account.referralCode)
                        .textSelection(.enabled)
                    ShareLink(item: "Try TunnelMaster VPN with my referral code: \(account.referralCode)")
                    Button("Register this device") {
                        perform {
                            try await service.registerDevice()
                            await service.refresh()
                        }
                    }
                    Button("Sign out") {
                        service.signOut()
                    }
                    Button("Delete my account", role: .destructive) {
                        confirmDelete = true
                    }
                    Notice(text: "Deleting your account does not cancel an Apple subscription. Cancel it in Apple subscription settings first if desired.")
                }
            } else {
                Section("Quick sign-in") {
                    ForEach(providers, id: \.self) { provider in
                        Button {
                            perform {
                                try await service.signIn(provider: provider.lowercased())
                            }
                        } label: {
                            Label("Continue with \(provider)", systemImage: provider == "Apple" ? "apple.logo" : "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(busy)
                    }
                }
                Section("Or use email") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Send confirmation email") {
                        perform {
                            try await service.emailLink(email)
                        }
                    }
                    TextField("Confirmation code from email", text: $confirmation)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Confirm account") {
                        perform {
                            try await service.confirmEmail(code: confirmation)
                        }
                    }
                }
                Section {
                    Button("Continue anonymously") {
                        dismiss()
                    }
                    Notice(text: "Your preferences apply only to this device in anonymous mode. Sign in to register up to three devices and enable iCloud settings sync. Signing in alone does not anonymize your connection.")
                }
            }
            Section {
                Text(message.isEmpty ? service.message : message).font(.footnote)
            }
        }
        .navigationTitle("Account")
        .confirmationDialog("Delete your account and service data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                perform {
                    try await service.deleteAccount()
                }
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer {
                busy = false
            }
            do {
                try await action()
                message = service.message
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var log: EventLog
    @State private var exportURL: URL?
    @State private var showMail = false
    @State private var error = ""
    private var supportEmail: String {
        Bundle.main.object(forInfoDictionaryKey: "SupportEmail") as? String ?? ""
    }
    var body: some View {
        List {
            Section {
                Picker("Show", selection: preferences.binding(\.logFilter)) {
                    ForEach(["Errors", "Warnings & errors", "All"], id: \.self) { filter in
                        Text(filter).tag(filter)
                    }
                }
                Toggle("Verbose", isOn: preferences.binding(\.verbose))
                Notice(text: "Operational events only, up to 1,000 per app session. No passwords, session tokens or browsing/DNS hostnames. Hiding this view does not change logging.")
                Button("Prepare text export") {
                    do {
                        exportURL = try log.export(preferences.value.logFilter)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                if let exportURL {
                    ShareLink("Save or share .txt", item: exportURL)
                    Button("Send to developer…") {
                        showMail = true
                    }
                    .disabled(!MFMailComposeViewController.canSendMail() || supportEmail.isEmpty)
                }
                Button("Clear logs", role: .destructive) {
                    log.clear()
                    exportURL = nil
                }
                Text(error).font(.caption)
            }
            ForEach(log.filtered(preferences.value.logFilter).reversed()) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.date.ISO8601Format()) · \(event.level)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(event.message)
                }
            }
        }
        .navigationTitle("Event log")
        .sheet(isPresented: $showMail) {
            if let exportURL {
                MailComposer(file: exportURL, recipient: supportEmail)
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On this device") {
                Text("Profiles and rules are stored locally. Passwords and imported keys are stored in the device Keychain. Logs contain operational events in memory; exported text remains wherever you save it.")
            }
            Section("Optional services") {
                Text("iCloud sync contains preferences, DNS rules and profile metadata. Account services receive authentication details, device registrations, purchase verification and referral information. Explicit family invitations send the entered recipient addresses to the invitation service.")
                Text("A remote VPN provider can observe your source address and traffic metadata. A DNS resolver receives forwarded DNS questions. A local DNS filter does not change your public IP or encrypt your traffic.")
            }
            Section("Development status") {
                Text("No analytics SDKs are included. A deployed VPN operator must publish an accurate privacy policy, disclose retention and gateway logging, and meet Apple's VPN requirements before selling the service. This source build does not promise a verified no-logs network.")
            }
        }
        .navigationTitle("Privacy")
    }
}
