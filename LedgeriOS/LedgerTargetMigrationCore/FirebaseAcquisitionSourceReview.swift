import Foundation

/// Source normalization only: a vendor purchase is not a Project client payment.
/// Retains the complete document and never derives a payer from price or placement.
package enum FirebaseAcquisitionSourceReview {
    package enum Payer: String, Sendable { case client, business }
    package enum Issue: String, Sendable {
        case invalidDocument, scopeMismatch, notPurchase, conflictingType, movementEvidence
        case missingPayer, unknownPayer, invalidAmount, cancellationRequiresMapping
    }
    package struct Result: Sendable {
        package let source: FirebaseSourceDocument
        package let payer: Payer?
        package let amountCents: Int64?
        package let issues: [Issue]
        /// This is eligibility to reconcile acquisition/Item relationships, not to load rows.
        package var canReconcileAcquisition: Bool { issues.isEmpty }
    }
    package struct ItemLinks: Sendable {
        package let declaredItemIDs: Set<String>
        package let currentItemIDs: Set<String>
        package let historicalItemIDs: Set<String>
        package let issues: Set<String>
        package var canMapCurrentMembership: Bool { issues.isEmpty }
    }
    /// Compare all three existing source relationships. Keep historical links
    /// separate: an old receipt link does not assert the Item's current placement.
    package static func reconcileItems(_ purchase: Result, documents: [FirebaseSourceDocument],
                                      lineage: [ReconciledFirebaseLineageEvidence]) -> ItemLinks {
        var issues = Set<String>()
        var declared = Set<String>(), current = Set<String>(), historical = Set<String>()
        guard purchase.canReconcileAcquisition, case .map(let fields) = purchase.source.fields else {
            return .init(declaredItemIDs: [], currentItemIDs: [], historicalItemIDs: [], issues: ["unresolved_purchase"])
        }
        let account = purchase.source.accountScopeID
        let transaction = purchase.source.documentPathSegments[3]
        if let itemIDs = fields.first(where: { $0.key == "itemIds" })?.value, itemIDs != .null {
            if case .array(let values) = itemIDs {
                for value in values {
                    guard case .string(let id) = value, !id.isEmpty, !id.contains("/") else {
                        issues.insert("invalid_item_ids"); continue
                    }
                    if !declared.insert(id).inserted { issues.insert("duplicate_item_id") }
                }
            } else { issues.insert("invalid_item_ids") }
        }
        // Shipped Transaction.itemIds is optional; the app reads nil as an
        // empty declared list. Keep absence/null in the raw source, but do not
        // invent a migration error solely because an older list was omitted.
        // Reverse Item links and lineage still participate below: nil never
        // overrides contradictory links or proves export completeness.
        var available = Set<String>()
        for item in documents where item.documentPathSegments.count == 4 && item.documentPathSegments[2] == "items" {
            guard item.accountScopeID == account, item.documentPathSegments[1] == account else { continue }
            let id = item.documentPathSegments[3]
            if !available.insert(id).inserted { issues.insert("duplicate_item_document") }
            guard item.evidenceKind == .record, case .map(let itemFields) = item.fields,
                  (try? item.fields.validated()) != nil else { issues.insert("invalid_item_document"); continue }
            if let embedded = itemFields.first(where: { $0.key == "accountId" })?.value,
               embedded != .string(account) { issues.insert("item_account_conflict"); continue }
            if itemFields.contains(where: { $0.key == "transactionId" && $0.value == .string(transaction) }) { current.insert(id) }
        }
        for edge in lineage where edge.source.sourceAccountScopeID == account
            && (edge.source.fromTransactionID == transaction || edge.source.toTransactionID == transaction) {
            if let item = edge.source.itemID { historical.insert(item) }
            if !edge.canAttemptMapping { issues.insert("unresolved_lineage") }
        }
        if !declared.union(historical).isSubset(of: available) { issues.insert("missing_item") }
        if declared != current { issues.insert("current_membership_mismatch") }
        // Preserve the historical set for subsequent movement mapping even when
        // the current arrays agree. This check never erases or rewrites history.
        return .init(declaredItemIDs: declared, currentItemIDs: current, historicalItemIDs: historical, issues: issues)
    }
    package static func review(_ source: FirebaseSourceDocument, accountID: String) -> Result {
        var issues: [Issue] = []
        guard source.evidenceKind == .record, source.documentPathSegments.count == 4,
              source.documentPathSegments[0] == "accounts", source.documentPathSegments[2] == "transactions",
              (try? source.fields.validated()) != nil, case .map(let fields) = source.fields else {
            return .init(source: source, payer: nil, amountCents: nil, issues: [.invalidDocument])
        }
        func field(_ key: String) -> FirebaseSourceValue? { fields.first { $0.key == key }?.value }
        if source.accountScopeID != accountID || source.documentPathSegments[1] != accountID {
            issues.append(.scopeMismatch)
        }
        if let embedded = field("accountId"), embedded != .string(accountID) { issues.append(.scopeMismatch) }
        if case .string(let type) = field("type"), type.lowercased() == "purchase" {
            if let alternate = field("transactionType"), alternate != .null {
                if case .string(let value) = alternate, value.lowercased() == "purchase" { }
                else { issues.append(.conflictingType) }
            }
        } else { issues.append(.notPurchase) }
        if field("isCanonicalInventorySale") == .bool(true) { issues.append(.movementEvidence) }
        if let direction = field("inventorySaleDirection"), direction != .null, direction != .string("") {
            issues.append(.movementEvidence)
        }
        if field("isCanceled") == .bool(true) { issues.append(.cancellationRequiresMapping) }
        if case .string(let status) = field("status"), ["cancelled", "canceled"].contains(status.lowercased()) {
            issues.append(.cancellationRequiresMapping)
        }
        let payer: Payer?
        switch field("purchasedBy") {
        case .string("client-card"): payer = .client
        case .string("design-business"): payer = .business
        case nil, .null: payer = nil; issues.append(.missingPayer)
        default: payer = nil; issues.append(.unknownPayer)
        }
        let amount: Int64?
        if case .integer(let raw) = field("amountCents"), let value = Int64(raw), value > 0 { amount = value }
        else { amount = nil; issues.append(.invalidAmount) }
        return .init(source: source, payer: payer, amountCents: amount, issues: issues)
    }
}
