/// Exact values recorded on a currently linked source Item. These are not a
/// reconstructed historical landed basis or an allocation of receipt-header tax.
package enum FirebaseReceiptItemPriceEvidence {
    package struct Price: Sendable {
        package let source: FirebaseSourceDocument
        package let purchasePriceCents: Int64?
        package let explicitlyRecordedTaxCents: Int64?
        package let issues: Set<String>
    }
    package static func read(_ item: FirebaseSourceDocument, sourceAccountID: String,
                             sourceTransactionID: String) -> Price {
        var issues = Set<String>()
        guard item.documentPathSegments.count == 4,
              item.documentPathSegments[0] == "accounts", item.documentPathSegments[1] == sourceAccountID,
              item.documentPathSegments[2] == "items", item.accountScopeID == sourceAccountID,
              item.evidenceKind == .record, (try? item.fields.validated()) != nil,
              case .map(let fields) = item.fields else {
            return .init(source: item, purchasePriceCents: nil, explicitlyRecordedTaxCents: nil, issues: ["invalid_item"])
        }
        func field(_ key: String) -> FirebaseSourceValue? { fields.first { $0.key == key }?.value }
        if let account = field("accountId"), account != .string(sourceAccountID) { issues.insert("account_mismatch") }
        guard field("transactionId") == .string(sourceTransactionID), issues.isEmpty else {
            return .init(source: item, purchasePriceCents: nil, explicitlyRecordedTaxCents: nil, issues: issues.union(["different_current_acquisition"]))
        }
        func cents(_ key: String, required: Bool) -> Int64? {
            guard let value = field(key), value != .null else {
                if required { issues.insert("missing_" + key) }
                return nil
            }
            guard case .integer(let text) = value, let amount = Int64(text), amount >= 0 else {
                issues.insert("invalid_" + key); return nil
            }
            return amount
        }
        let price = cents("purchasePriceCents", required: true)
        let tax = cents("taxAmountPurchasePriceCents", required: false)
        // Quantity, projectPriceCents, market value and header tax rate do not
        // alter either value. Missing tax is unknown, not zero.
        return .init(source: item, purchasePriceCents: price, explicitlyRecordedTaxCents: tax, issues: issues)
    }
}
