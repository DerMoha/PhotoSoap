import SwiftUI
import Combine
import StoreKit

enum AdRemovalConfig {
    static let freeUnlockDeletedCount = 2000
    static let productID = "com.photosoap.removeads"
    static let fallbackPrice = "$0.99"
}

enum AdRemovalUnlockSource {
    case none
    case purchased
    case earned
    case coupon
}

@MainActor
final class AdRemovalPurchaseService: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var hasPurchasedEntitlement = false
    @Published private(set) var hasEarnedEntitlement = false
    @Published private(set) var hasCouponEntitlement = false
    @Published private(set) var currentDeletedCount = 0
    @Published var errorMessage: String?

    #if DEBUG
    @Published private(set) var devOverrideAdFree = false
    private static let devOverrideKey = "devOverrideAdFree"
    #endif

    @AppStorage("hasPurchasedRemoveAds") private var hasPurchasedRemoveAds = false
    private static let couponKey = "hasCouponAdFree"
    private var updatesTask: Task<Void, Never>?
    private let analyticsService: AnalyticsService

    init(analyticsService: AnalyticsService, shouldObserveTransactions: Bool = true) {
        self.analyticsService = analyticsService
        hasPurchasedEntitlement = hasPurchasedRemoveAds
        hasCouponEntitlement = UserDefaults.standard.bool(forKey: Self.couponKey)
        #if DEBUG
        devOverrideAdFree = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        #endif

        guard shouldObserveTransactions else {
            return
        }

        updatesTask = Task {
            await loadProduct()
            await refreshEntitlement()
            await observeTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var displayPrice: String {
        product?.displayPrice ?? AdRemovalConfig.fallbackPrice
    }

    var hasAdRemovalEntitlement: Bool {
        #if DEBUG
        if devOverrideAdFree { return true }
        #endif
        return hasPurchasedEntitlement || hasEarnedEntitlement || hasCouponEntitlement
    }

    var unlockSource: AdRemovalUnlockSource {
        if hasPurchasedEntitlement {
            return .purchased
        }

        if hasCouponEntitlement {
            return .coupon
        }

        if hasEarnedEntitlement {
            return .earned
        }

        return .none
    }

    var deleteProgress: Double {
        min(1.0, Double(currentDeletedCount) / Double(AdRemovalConfig.freeUnlockDeletedCount))
    }

    var remainingDeletesForUnlock: Int {
        max(0, AdRemovalConfig.freeUnlockDeletedCount - currentDeletedCount)
    }

    func purchase() async {
        guard let product else {
            errorMessage = "Unable to load purchase option."
            return
        }

        analyticsService.track(.purchaseStarted(productID: product.id))

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                analyticsService.track(.purchaseCompleted(productID: transaction.productID, source: "purchase"))
                await handleVerified(transaction)
            case .pending:
                errorMessage = "Purchase pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        analyticsService.track(.purchaseRestoreStarted())

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            analyticsService.track(.purchaseRestoreCompleted(hasEntitlement: hasPurchasedEntitlement))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEarnedEntitlement(stats: UserStats) {
        let hadEarnedEntitlement = hasEarnedEntitlement
        currentDeletedCount = stats.totalDeleted
        hasEarnedEntitlement = stats.totalDeleted >= AdRemovalConfig.freeUnlockDeletedCount

        if !hadEarnedEntitlement && hasEarnedEntitlement {
            analyticsService.track(.loyaltyUnlockEarned(threshold: AdRemovalConfig.freeUnlockDeletedCount))
        }
    }

    func applyPurchasedEntitlement(_ hasEntitlement: Bool) {
        hasPurchasedEntitlement = hasEntitlement
        hasPurchasedRemoveAds = hasEntitlement
    }

    func applyCouponEntitlement(_ hasEntitlement: Bool) {
        hasCouponEntitlement = hasEntitlement
        UserDefaults.standard.set(hasEntitlement, forKey: Self.couponKey)
    }

    #if DEBUG
    func setDevOverrideAdFree(_ enabled: Bool) {
        devOverrideAdFree = enabled
        UserDefaults.standard.set(enabled, forKey: Self.devOverrideKey)
    }
    #endif

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [AdRemovalConfig.productID])
            product = products.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshEntitlement() async {
        var hasEntitlement = false

        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AdRemovalConfig.productID {
                hasEntitlement = true
            }
        }

        applyPurchasedEntitlement(hasEntitlement)
    }

    private func observeTransactionUpdates() async {
        for await result in StoreKit.Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                guard transaction.productID == AdRemovalConfig.productID else {
                    await transaction.finish()
                    continue
                }

                await handleVerified(transaction)
            } catch {
                continue
            }
        }
    }

    private func handleVerified(_ transaction: StoreKit.Transaction) async {
        await transaction.finish()
        await refreshEntitlement()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw PurchaseError.failedVerification
        }
    }
}

enum PurchaseError: Error {
    case failedVerification
}
