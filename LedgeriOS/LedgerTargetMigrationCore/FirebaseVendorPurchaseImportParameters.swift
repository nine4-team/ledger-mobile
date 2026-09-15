import Foundation
import LedgerTargetCore

/// Explicit reconciled relationships, not an inference from current placement or
/// current Item prices. Unknown historical cost must remain nil.
package struct FirebaseVendorPurchaseItemMapping: Sendable {
    package let sourceItemID: String
    package let relationshipID: String
    package let targetItemID: ItemID
    package let amountMinorUnits: Int64?
    package let membership: TransactionReceiptSnapshot.Membership
    package init(sourceItemID: String, relationshipID: String, targetItemID: ItemID,
                 amountMinorUnits: Int64?, membership: TransactionReceiptSnapshot.Membership) {
        self.sourceItemID = sourceItemID
        self.relationshipID = relationshipID
        self.targetItemID = targetItemID
        self.amountMinorUnits = amountMinorUnits
        self.membership = membership
    }
}

package enum FirebaseVendorPurchaseImportFailure: Error {
    case incompleteOrDuplicateItems, invalidAmount, invalidRelationship, currencyMismatch
}

package struct FirebaseVendorPurchaseImportParameters: Encodable, Sendable {
    package struct Item: Encodable, Sendable {
        let id: String
        let itemId: String
        let amountMinorUnits: String?
        let membershipKind: String
        private enum CodingKeys: String, CodingKey { case id, itemId, amountMinorUnits, membershipKind }
        package func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(itemId, forKey: .itemId)
            try c.encode(amountMinorUnits, forKey: .amountMinorUnits) // explicit JSON null
            try c.encode(membershipKind, forKey: .membershipKind)
        }
    }
    package struct Line: Encodable, Sendable {
        let id: String
        let description: String
        let amountMinorUnits: String
        let effect: String
        let quantity: String?
    }
    package let p_id: String
    package let p_account_id: String
    package let p_scope_kind: String
    package let p_project_id: String?
    package let p_client_id: String?
    package let p_category_id: String
    package let p_amount: String
    package let p_currency: String
    package let p_lines: [Line]
    package let p_items: [Item]
    package let p_source_account: String
    package let p_source_document: String
    package let p_source_bytes: String

    private enum CodingKeys: String, CodingKey {
        case p_id, p_account_id, p_scope_kind, p_project_id, p_client_id, p_category_id,
             p_amount, p_currency, p_lines, p_items, p_source_account, p_source_document, p_source_bytes
    }
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_id, forKey: .p_id)
        try c.encode(p_account_id, forKey: .p_account_id)
        try c.encode(p_scope_kind, forKey: .p_scope_kind)
        try c.encode(p_project_id, forKey: .p_project_id)
        try c.encode(p_client_id, forKey: .p_client_id)
        try c.encode(p_category_id, forKey: .p_category_id)
        try c.encode(p_amount, forKey: .p_amount)
        try c.encode(p_currency, forKey: .p_currency)
        try c.encode(p_lines, forKey: .p_lines)
        try c.encode(p_items, forKey: .p_items)
        try c.encode(p_source_account, forKey: .p_source_account)
        try c.encode(p_source_document, forKey: .p_source_document)
        try c.encode(p_source_bytes, forKey: .p_source_bytes)
    }

    package static func make(plan: FirebaseAcquisitionConversion.Plan, targetID: TransactionID,
                             targetCategoryID: BudgetCategoryID, currency: CurrencyCode,
                             items: [FirebaseVendorPurchaseItemMapping], lines: [NonItemReceiptLine]) throws -> Self {
        let expected = plan.sourceItemIDs.union(plan.historicalItemIDs)
        guard Set(items.map(\.sourceItemID)) == expected, items.count == expected.count,
              Set(items.map(\.relationshipID)).count == items.count,
              Set(items.map(\.targetItemID)).count == items.count else {
            throw FirebaseVendorPurchaseImportFailure.incompleteOrDuplicateItems
        }
        guard items.allSatisfy({ $0.amountMinorUnits.map { $0 >= 0 } ?? true }) else {
            throw FirebaseVendorPurchaseImportFailure.invalidAmount
        }
        // The same existing identifier contract used by target entities; this
        // validates the supplied relationship identity without inventing one.
        for item in items {
            guard (try? ItemID(validating: item.relationshipID)) != nil else {
                throw FirebaseVendorPurchaseImportFailure.invalidRelationship
            }
        }
        guard lines.allSatisfy({ $0.magnitude.currency == currency }) else {
            throw FirebaseVendorPurchaseImportFailure.currencyMismatch
        }
        let scope = plan.classification.scope
        let source = plan.source
        let bytes = try source.canonicalEvidenceData()
        return .init(p_id: targetID.rawValue, p_account_id: scope.accountId.rawValue,
            p_scope_kind: scope.ownerKind == .project ? "project" : "business_inventory", p_project_id: scope.projectId?.rawValue,
            p_client_id: scope.clientId?.rawValue, p_category_id: targetCategoryID.rawValue,
            p_amount: String(plan.amountCents), p_currency: currency.rawValue,
            p_lines: lines.map { .init(id: $0.id.rawValue, description: $0.description.rawValue,
                amountMinorUnits: String($0.magnitude.minorUnits), effect: $0.effect.rawValue,
                quantity: $0.quantity.map(String.init)) },
            p_items: items.sorted { $0.relationshipID.utf8.lexicographicallyPrecedes($1.relationshipID.utf8) }.map {
                .init(id: $0.relationshipID, itemId: $0.targetItemID.rawValue,
                    amountMinorUnits: $0.amountMinorUnits.map(String.init), membershipKind: $0.membership.rawValue)
            }, p_source_account: source.accountScopeID, p_source_document: source.documentPathSegments[3],
            p_source_bytes: "\\x" + bytes.map { String(format: "%02x", $0) }.joined())
    }
}
