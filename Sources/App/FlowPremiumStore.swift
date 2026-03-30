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
    @Published var lastErrorMessage: String?

    private let appSettings: AppSettingsStore
    private var transactionUpdatesTask: Task<Void, Never>?

    init(appSettings: AppSettingsStore? = nil) {
        self.appSettings = appSettings ?? AppSettingsStore.shared
        transactionUpdatesTask = observeTransactionUpdates()

        Task {
            await refreshProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var flowPlusProduct: Product? {
        products.first(where: { $0.id == FlowPlusProduct.monthly.rawValue }) ?? products.first
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: FlowPlusProduct.allCases.map(\.rawValue))
            lastErrorMessage = nil
        } catch {
            products = []
            lastErrorMessage = "Couldn't load Flow Plus pricing right now."
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
        appSettings.updatePremiumThemesUnlocked(!activeIDs.isEmpty)
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
                lastErrorMessage = "Flow Plus purchase status is unavailable."
                return .failed
            }
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed
        }
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            lastErrorMessage = nil
            await refreshEntitlements()
        } catch {
            lastErrorMessage = "Couldn't restore Flow Plus purchases right now."
        }
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
                return "We couldn't verify your Flow Plus purchase."
            }
        }
    }
}
