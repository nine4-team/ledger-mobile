import LedgerTargetCore
import PowerSync

enum ProjectInvoicingItemLocalReader {
    enum Failure: Error { case unavailable }

    /// Charge-source rows only. The eventual workspace provider must separately
    /// establish stream completeness and compose credit/Expense/Fee sources.
    static func readCharges(transaction: any Transaction, accountId: AccountID,
                            principalId: PrincipalID, projectId: ProjectID) throws -> [ProjectInvoicingItem] {
        try requireAccess(transaction: transaction, accountId: accountId, principalId: principalId, projectId: projectId)
        return try readAuthorizedCharges(transaction: transaction, accountId: accountId, principalId: principalId, projectId: projectId)
    }

    static func requireAccess(transaction: any Transaction, accountId: AccountID,
                              principalId: PrincipalID, projectId: ProjectID) throws {
        let allowed = try transaction.get(sql: """
            SELECT EXISTS(SELECT 1 FROM spike_account_memberships m JOIN spike_projects p ON p.account_id=m.account_id
              WHERE m.account_id=? AND m.principal_id=? AND m.state='active' AND m.financial_access='full' AND p.id=?) AS allowed
            """, parameters: [accountId.rawValue, principalId.rawValue, projectId.rawValue]) { try $0.getInt(name: "allowed") == 1 }
        guard allowed else { throw Failure.unavailable }
    }

    static func readAuthorizedCharges(transaction: any Transaction, accountId: AccountID,
                                      principalId: PrincipalID, projectId: ProjectID) throws -> [ProjectInvoicingItem] {
        // Reuse the existing scope, revision, amount and frozen-membership validator.
        // Only its physical-location filter changes for this historical read.
        let evidence = try ItemClientPaymentConnectionLocalReader.read(transaction: transaction,
            accountId: accountId, principalId: principalId, projectId: projectId, includeHistoricalPlacements: true)
        let occurrences = Dictionary(uniqueKeysWithValues: evidence.values.flatMap(\.evidence.billableOccurrences).map { ($0.id.rawValue, $0) })
        return try transaction.getAll(sql: """
            SELECT c.id,c.amount_minor_units,c.currency,COALESCE(i.name,i.description) AS title,
              category.display_name AS category_name,l.description AS frozen_description
            FROM item_charge_occurrences c
            LEFT JOIN spike_items i ON i.account_id=c.account_id AND i.id=c.item_id
            LEFT JOIN spike_budget_categories category ON category.account_id=c.account_id AND category.id=c.category_id
            LEFT JOIN collected_invoice_lines l ON l.account_id=c.account_id AND l.source_kind='item' AND l.source_id=c.id
            WHERE c.account_id=? AND c.project_id=? AND c.withdrawn_at IS NULL ORDER BY c.id
            """, parameters: [accountId.rawValue, projectId.rawValue]) { cursor in
                guard let occurrence = occurrences[try cursor.getString(name: "id")],
                      let amount = Int64(try cursor.getString(name: "amount_minor_units")) else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                let paid = occurrence.phase.kind == .frozenPaid
                let title = try cursor.getStringOptional(name: paid ? "frozen_description" : "title")
                guard let title else { throw Failure.unavailable }
                return try ProjectInvoicingItem(occurrence: occurrence,
                    amount: Money(minorUnits: amount, currency: CurrencyCode(validating: cursor.getString(name: "currency"))),
                    availability: paid ? .paid : .available, title: title,
                    // A current renamed category is not the paid category snapshot.
                    categoryName: paid ? nil : cursor.getStringOptional(name: "category_name"))
            }
    }
}
