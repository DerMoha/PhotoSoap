import SwiftUI
import Combine
import StoreKit

enum AdRemovalConfig {
    static let freeUnlockDeletedCount = 2000
    static let productID = "com.photosoap.removeads"
    static let fallbackPrice = "$0.99"
}

@MainActor
final class AdRemovalPurchaseService: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    @AppStorage("hasPurchasedRemoveAds") private var hasPurchasedRemoveAds = false
    private var updatesTask: Task<Void, Never>?

    init() {
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

    func purchase() async {
        guard let product else {
            errorMessage = "Unable to load purchase option."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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

        hasPurchasedRemoveAds = hasEntitlement
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
