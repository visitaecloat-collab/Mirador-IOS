import Foundation
import StoreKit

/// Equivalente de `PlayBillingManager.kt` en iOS mediante StoreKit 2:
/// - Productos: `mirador_weekly`, `mirador_monthly`, `mirador_quarterly`
/// - Soporta compra, restauración de compras, verificación JWS y envío al backend Supabase
@MainActor
final class StoreKitSubscriptionService: ObservableObject {
    @Published var products: [Product] = []
    @Published var activeProductId: String?
    @Published var isAutoRenewEnabled: Bool = true
    @Published var expirationDate: Date?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?
    private let supabase = SupabaseService()

    init() {
        updatesTask = Task {
            await listenForTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isBusy = true
        defer { isBusy = false }
        let ids = Set(SubscriptionPlanType.allCases.map(\.rawValue))
        do {
            let storeProducts = try await Product.products(for: ids)
            self.products = storeProducts.sorted { $0.price < $1.price }
            await refreshCurrentEntitlements()
        } catch {
            self.errorMessage = "No se pudieron cargar las tarifas de App Store: \(error.localizedDescription)"
        }
    }

    func purchase(product: Product, accessToken: String?) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifyResult(verification)
                if let token = accessToken, !token.isEmpty {
                    try? await supabase.verifyStoreKitTransaction(
                        accessToken: token,
                        productId: transaction.productID,
                        transactionId: transaction.id,
                        originalTransactionId: transaction.originalID,
                        signedJWS: verification.jwsRepresentation
                    )
                }
                await transaction.finish()
                await refreshCurrentEntitlements()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "No se pudo completar la suscripción: \(error.localizedDescription)"
            return false
        }
    }

    func restorePurchases() async {
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refreshCurrentEntitlements()
    }

    func refreshCurrentEntitlements() async {
        var foundId: String?
        var expiry: Date?

        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement, tx.revocationDate == nil {
                foundId = tx.productID
                expiry = tx.expirationDate
                break
            }
        }
        self.activeProductId = foundId
        self.expirationDate = expiry
    }

    private func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            if case .verified(let tx) = update {
                await tx.finish()
                await refreshCurrentEntitlements()
            }
        }
    }

    private func verifyResult<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "MiradorStoreKit", code: 403, userInfo: [NSLocalizedDescriptionKey: "Firma JWS de StoreKit inválida"])
        case .verified(let safe):
            return safe
        }
    }
}
