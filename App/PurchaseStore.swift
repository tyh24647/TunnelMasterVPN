import Foundation
import Combine
import StoreKit

struct Plan: Identifiable {
    let family: Bool
    let term: String
    let proposedPrice: String
    var id: String {
        "com.tyh24647.TunnelDojo.\(family ? "family" : "individual").\(term)"
    }
    static let all: [Plan] = [
        Plan(family: false, term: "weekly", proposedPrice: "$0.99 / week"),
        Plan(family: false, term: "monthly", proposedPrice: "$2.99 / month"),
        Plan(family: false, term: "yearly", proposedPrice: "$24.99 / year"),
        Plan(family: false, term: "lifetime", proposedPrice: "$69.99 once"),
        Plan(family: true, term: "weekly", proposedPrice: "$2.99 / week"),
        Plan(family: true, term: "monthly", proposedPrice: "$9.99 / month"),
        Plan(family: true, term: "yearly", proposedPrice: "$49.99 / year"),
        Plan(family: true, term: "lifetime", proposedPrice: "$199.99 once")
    ]
}

/// StoreKit verification precedes provisioning. Unacknowledged transactions remain retryable.
@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var entitlements = Set<String>()
    @Published var message = ""
    @Published var busy = false
    @Published var eligibleTrialIDs = Set<String>()
    private var updates: Task<Void, Never>?
    let service: ServiceClient

    init(service: ServiceClient) {
        self.service = service
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else {
                    return
                }
                do {
                    try await self.deliver(result)
                } catch {
                    self.message = error.localizedDescription
                }
                await self.refreshEntitlements()
            }
        }
        Task {
            await load()
        }
    }

    func load() async {
        do {
            products = try await Product.products(for: Plan.all.map(\.id))
            for product in products {
                if let subscription = product.subscription,
                   subscription.introductoryOffer?.paymentMode == .freeTrial {
                    let eligible = await subscription.isEligibleForIntroOffer
                    if eligible {
                        eligibleTrialIDs.insert(product.id)
                    }
                }
            }
            await refreshEntitlements()
        } catch {
            message = "Unable to load App Store products. \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        guard !busy else {
            return false
        }
        guard service.account != nil, service.purchasesEnabled, service.catalogIsLive, service.servers.contains(where: { $0.online }) else {
            message = "Sign in and configure a production-ready VPN service before purchasing."
            return false
        }
        busy = true
        defer {
            busy = false
        }
        do {
            guard let id = service.account?.id, let token = UUID(uuidString: id) else {
                throw ServiceError(message: "The service account identifier is invalid.")
            }
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result):
                try await deliver(result)
                await refreshEntitlements()
                return true
            case .pending:
                message = "Waiting for purchase approval. No invitation has been sent."
            case .userCancelled:
                message = "Purchase cancelled."
            @unknown default:
                message = "Purchase state is not recognized."
            }
        } catch {
            message = error.localizedDescription
        }
        return false
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = result else {
            throw ServiceError(message: "The App Store transaction could not be verified.")
        }
        guard Plan.all.contains(where: { $0.id == transaction.productID }) else {
            return
        }
        let reply: ServiceReply = try await service.request("v1/purchases/verify", method: "POST", body: [
            "signedTransaction": result.jwsRepresentation
        ])
        await transaction.finish()
        message = reply.message
        await service.refresh()
    }

    func restore() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                try await deliver(result)
            }
            await refreshEntitlements()
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var active = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               !transaction.isUpgraded,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                active.insert(transaction.productID)
            }
        }
        entitlements = active
    }
}
