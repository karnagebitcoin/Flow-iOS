import Foundation
import StoreKit
import SwiftUI

@MainActor
final class FlowPremiumStore: ObservableObject {
    enum PurchaseOutcome {
        case success
        case pending
        case cancelled
        case failed
    }

    enum FlowPlusProduct: String, CaseIterable {
        case monthly = "com.21media.flow.flowplus.monthly"
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductIDs = Set<String>()
    @Published private(set) var isFlowPlusActive = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var isEligibleForFlowPlusIntroOffer = false
    @Published var lastErrorMessage: String?

    private let appSettings: AppSettingsStore
    private var transactionUpdatesTask: Task<Void, Never>?

    init(appSettings: AppSettingsStore? = nil) {
        self.appSettings = appSettings ?? AppSettingsStore.shared
        transactionUpdatesTask = observeTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var flowPlusProduct: Product? {
        products.first(where: { $0.id == FlowPlusProduct.monthly.rawValue }) ?? products.first
    }

    var flowPlusIntroOffer: Product.SubscriptionOffer? {
        flowPlusProduct?.subscription?.introductoryOffer
    }

    var flowPlusTrialMarketingText: String? {
        guard isEligibleForFlowPlusIntroOffer, let offer = flowPlusIntroOffer else { return nil }
        return offer.flowPlusTrialMarketingText
    }

    var flowPlusMonthlyPriceText: String {
        flowPlusProduct?.displayPrice ?? "$5.99"
    }

    var flowPlusPurchaseButtonTitle: String {
        "Try it free for 7 days"
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: FlowPlusProduct.allCases.map(\.rawValue))
            await refreshIntroOfferEligibility()
            lastErrorMessage = nil
        } catch {
            products = []
            isEligibleForFlowPlusIntroOffer = false
            lastErrorMessage = "Couldn't load Halo Plus pricing right now."
        }
    }

    func refreshEntitlements() async {
        var activeIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard FlowPlusProduct(rawValue: transaction.productID) != nil else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                continue
            }
            activeIDs.insert(transaction.productID)
        }

        activeProductIDs = activeIDs
        isFlowPlusActive = !activeIDs.isEmpty
        appSettings.updateFlowPlusAccess(!activeIDs.isEmpty)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                lastErrorMessage = nil
                await refreshEntitlements()
                return .success
            case .pending:
                lastErrorMessage = "Your purchase is pending approval."
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                lastErrorMessage = "Halo Plus purchase status is unavailable."
                return .failed
            }
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed
        }
    }

    func purchaseFlowPlus() async -> PurchaseOutcome {
        if flowPlusProduct == nil {
            await refreshProducts()
        }

        guard let product = flowPlusProduct else {
            lastErrorMessage = "Couldn't load Halo Plus pricing right now. Please try again in a moment."
            return .failed
        }

        return await purchase(product)
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            lastErrorMessage = nil
            await refreshEntitlements()
        } catch {
            lastErrorMessage = "Couldn't restore Halo Plus purchases right now."
        }
    }

    private func refreshIntroOfferEligibility() async {
        guard
            let subscription = flowPlusProduct?.subscription,
            let offer = subscription.introductoryOffer,
            offer.paymentMode == .freeTrial
        else {
            isEligibleForFlowPlusIntroOffer = false
            return
        }

        isEligibleForFlowPlusIntroOffer = await subscription.isEligibleForIntroOffer
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.refreshEntitlements()
                } catch {
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let signedType):
            return signedType
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "We couldn't verify your Halo Plus purchase."
            }
        }
    }
}

private extension Product.SubscriptionOffer {
    var flowPlusTrialMarketingText: String? {
        guard paymentMode == .freeTrial else { return nil }

        switch period.unit {
        case .week where period.value * max(periodCount, 1) == 1:
            return "7-day free trial"
        default:
            let totalValue = period.value * max(periodCount, 1)
            let unitLabel: String
            switch period.unit {
            case .day:
                unitLabel = "day"
            case .week:
                unitLabel = "week"
            case .month:
                unitLabel = "month"
            case .year:
                unitLabel = "year"
            @unknown default:
                unitLabel = "period"
            }
            let durationText = totalValue == 1 ? "1 \(unitLabel)" : "\(totalValue) \(unitLabel)s"
            return "\(durationText) free trial"
        }
    }
}
