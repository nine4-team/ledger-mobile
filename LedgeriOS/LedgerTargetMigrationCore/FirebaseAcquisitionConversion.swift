import LedgerTargetCore

/// A deterministic acquisition plan. It is not a collection, placement command,
/// import authorization, or assertion that receipt-line allocation is complete.
package enum FirebaseAcquisitionConversion {
    package enum Failure: String, Sendable {
        case sourceProjectMismatch, targetRequiresProject, unresolvedSource, unresolvedItemLinks, unresolvedCategory
        case businessExpenseRequiresMapping
    }
    package struct Plan: Sendable {
        package let source: FirebaseSourceDocument
        package let classification: TransactionClassification
        package let amountCents: Int64
        package let sourceItemIDs: Set<String>
        package let historicalItemIDs: Set<String>
        package let sourceProjectScope: TransactionScope
        package let sourceCategory: FirebaseSourceDocument
        package let categoryKind: BudgetCategoryKind
    }
    package enum Result: Sendable {
        case planned(Plan)
        case unresolved(Failure)
    }
    package static func convert(_ source: FirebaseSourceDocument, sourceAccountID: String,
                                sourceProjectID: String, targetProjectScope: TransactionScope,
                                documents: [FirebaseSourceDocument],
                                lineage: [ReconciledFirebaseLineageEvidence]) -> Result {
        guard targetProjectScope.ownerKind == .project else { return .unresolved(.targetRequiresProject) }
        guard case .map(let fields) = source.fields,
              fields.contains(where: { $0.key == "projectId" && $0.value == .string(sourceProjectID) }) else {
            return .unresolved(.sourceProjectMismatch)
        }
        let review = FirebaseAcquisitionSourceReview.review(source, accountID: sourceAccountID)
        guard review.canReconcileAcquisition, let payer = review.payer, let amount = review.amountCents else {
            return .unresolved(.unresolvedSource)
        }
        guard case .string(let categoryID) = fields.first(where: { $0.key == "budgetCategoryId" })?.value else {
            return .unresolved(.unresolvedCategory)
        }
        let categories = documents.filter { $0.documentPathSegments == ["accounts", sourceAccountID, "presets", "default", "budgetCategories", categoryID] }
        guard categories.count == 1, let category = categories.first,
              category.accountScopeID == sourceAccountID, category.evidenceKind == .record,
              (try? category.fields.validated()) != nil, case .map(let categoryFields) = category.fields,
              !categoryFields.contains(where: { $0.key == "accountId" && $0.value != .string(sourceAccountID) }),
              case .map(let metadata) = categoryFields.first(where: { $0.key == "metadata" })?.value,
              case .string(let rawKind) = metadata.first(where: { $0.key == "categoryType" })?.value,
              let kind = BudgetCategoryKind(rawValue: rawKind) else { return .unresolved(.unresolvedCategory) }
        let links = FirebaseAcquisitionSourceReview.reconcileItems(review, documents: documents, lineage: lineage)
        guard links.canMapCurrentMembership else { return .unresolved(.unresolvedItemLinks) }
        // D-009: business-paid General project costs belong to Expense/Invoicing,
        // not the vendor-Purchase importer. Historical settlement and source
        // relationships still need explicit mapping; never invent a fresh debt
        // merely because a legacy category currently says General.
        if payer == .business, kind == .general {
            return .unresolved(.businessExpenseRequiresMapping)
        }
        // D-001/D-020/D-021: retain who actually paid. Business money never
        // becomes a pre-collection Project Purchase just because Items are there.
        let moneyScope = payer == .client ? targetProjectScope
            : TransactionScope.businessInventory(accountId: targetProjectScope.accountId)
        guard let classification = try? TransactionClassification(type: .purchase, scope: moneyScope, role: .standalone) else {
            return .unresolved(.targetRequiresProject)
        }
        return .planned(.init(source: source, classification: classification, amountCents: amount,
            sourceItemIDs: links.currentItemIDs, historicalItemIDs: links.historicalItemIDs,
            sourceProjectScope: targetProjectScope, sourceCategory: category, categoryKind: kind))
    }
}
