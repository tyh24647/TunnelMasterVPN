import SwiftUI
import StoreKit

struct PlansView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @EnvironmentObject private var service: ServiceClient
    @State private var family = false
    @State private var code = ""
    @State private var emails = ""
    @State private var notifyFamily = false
    @State private var showRedeem = false
    @State private var message = ""
    var body: some View {
        List {
            Section {
                Label("A wider world.", systemImage: "sparkles").font(.largeTitle.bold())
                Text("Premium capacity and more locations for your devices.")
                    .foregroundStyle(.secondary)
                Toggle("Family membership", isOn: $family)
                Text(family ? "Unlimited registered devices for your family membership. Apple Family Sharing supports you and up to five family members." : "Individual accounts can register up to three devices.")
                    .font(.footnote)
                if !service.purchasesEnabled {
                    Notice(text: "Plan preview. Purchasing is disabled until live VPN service is configured.")
                }
            }
            Section("Choose your plan") {
                ForEach(Plan.all.filter { $0.family == family }) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(plan.term.capitalized).font(.headline)
                            Spacer()
                            if let product = purchases.products.first(where: { $0.id == plan.id }) {
                                Text(product.displayPrice)
                                Button("Choose") {
                                    Task {
                                        let paid = await purchases.purchase(product)
                                        if paid, notifyFamily, service.account?.family == true, !emails.isEmpty {
                                            do {
                                                try await service.inviteFamily(emails)
                                                message = service.message
                                            } catch {
                                                message = error.localizedDescription
                                            }
                                        }
                                    }
                                }
                                .disabled(purchases.busy || !service.purchasesEnabled || service.account == nil)
                            } else {
                                Text(plan.proposedPrice).foregroundStyle(.secondary)
                            }
                        }
                        if purchases.eligibleTrialIDs.contains(plan.id) {
                            Text("Eligible free trial shown in Apple's purchase confirmation.")
                                .font(.caption).foregroundStyle(.tint)
                        } else if plan.term != "lifetime" {
                            Text("Planned: 7-day introductory trial for eligible subscribers.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("One-time purchase. A separate service trial is required for lifetime access; it never auto-charges.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            if family {
                Section("Family invitations") {
                    Toggle("Notify my family after verified payment", isOn: $notifyFamily)
                    TextField("Family email addresses, comma-separated", text: $emails, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    Notice(text: "Only enter people you want invited. Apple does not provide their addresses. The server verifies the purchase before queuing invitations; shared recipients cannot re-share ownership.")
                    Button("Send invitations for existing membership") {
                        Task {
                            do {
                                try await service.inviteFamily(emails)
                                message = service.message
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                    .disabled(service.account?.family != true || !notifyFamily || emails.isEmpty)
                    Text("Manage Apple's Share with Family switch in Settings → Apple Account → Subscriptions.")
                        .font(.caption)
                }
            }
            Section("Lifetime service trial") {
                Button("Start separate 7-day trial") {
                    Task {
                        do {
                            try await service.startLifetimeTrial()
                            message = service.message
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(!service.catalogIsLive || service.account == nil)
                Notice(text: "No payment is taken automatically. This service trial must not be combined with referral credit. Family trial sharing requires a verified family product.")
            }
            Section("Discounts & referrals") {
                Button("Redeem an App Store offer code") {
                    showRedeem = true
                }
                TextField("Referral code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Apply referral") {
                    Task {
                        do {
                            try await service.redeemReferral(code)
                            message = service.message
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                Notice(text: "A valid referral can grant one service month after server eligibility checks. It does not silently change an existing Apple billing schedule or stack introductory offers.")
            }
            Section {
                Button("Restore purchases") {
                    Task {
                        await purchases.restore()
                    }
                }
                Link("Manage subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Text(purchases.message).font(.footnote)
                Text(message).font(.footnote)
                Text("Subscriptions renew automatically unless cancelled in Apple subscription settings. Apple's confirmation displays the actual local price, trial, renewal term and billing date. Lifetime is a non-consumable. Prices above are requested US prices until App Store products load.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Apple standard license", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                NavigationLink("Privacy & data use") {
                    PrivacyView()
                }
            }
        }
        .navigationTitle("Premium")
        .offerCodeRedemption(isPresented: $showRedeem)
    }
}
