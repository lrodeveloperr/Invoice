import Foundation
import InvoiceDomain

#if canImport(StoreKit)
import Combine
import StoreKit

@MainActor
public final class StoreKitEntitlementStore: ObservableObject {
    @Published public private(set) var product: Product?
    @Published public private(set) var hasPro = false
    @Published public private(set) var lastErrorID: String?

    public let productID: String
    private var updatesTask: Task<Void, Never>?

    public init(productID: String) {
        self.productID = productID
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    public var displayPrice: String? { product?.displayPrice }

    public func load() async {
        await refreshEntitlement()
        do {
            product = try await Product.products(for: [productID]).first
            lastErrorID = nil
        } catch {
            lastErrorID = "storekit_product_load_failed"
        }
    }

    public func purchase() async -> Bool {
        guard let product else { lastErrorID = "storekit_product_unavailable"; return false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlement()
                return hasPro
            case .pending:
                lastErrorID = "storekit_purchase_pending"
                return false
            case .userCancelled:
                lastErrorID = nil
                return false
            @unknown default:
                lastErrorID = "storekit_purchase_unknown"
                return false
            }
        } catch {
            lastErrorID = "storekit_purchase_failed"
            return false
        }
    }

    public func restorePurchase() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastErrorID = "storekit_restore_failed"
        }
    }

    public func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.revocationDate == nil else { continue }
            entitled = true
        }
        hasPro = entitled
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified: throw InvoiceError.corruptData("unverified_storekit_transaction")
        }
    }
}
#endif
