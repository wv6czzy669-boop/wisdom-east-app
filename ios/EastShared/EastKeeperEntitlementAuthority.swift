import Foundation
import StoreKit

/// StoreKit 2 is the sole Keeper authority in both Runner and the interactive
/// widget. Persisted Flutter/App Group booleans are presentation caches only;
/// the widget may reuse only a short, timestamped result that this authority
/// or Runner just verified while the person completes one ritual.
enum EastKeeperEntitlementAuthority {
    static let keeperProductID = "com.dailywisdomeast.keeper"

    static func isCurrentKeeperTransaction(
        productID: String,
        revocationDate: Date?
    ) -> Bool {
        productID == keeperProductID && revocationDate == nil
    }

    static func currentEntitlement() async -> Bool {
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else {
                continue
            }
            if isCurrentKeeperTransaction(
                productID: transaction.productID,
                revocationDate: transaction.revocationDate
            ) {
                return true
            }
        }
        return false
    }
}
