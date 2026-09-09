import LedgerTargetCore
import PowerSync

enum ItemClientPaymentConnectionLocalReader {
    /// Project-wide browsing read, optionally narrowed to one current placement
    /// for Item detail. Absence remains unknown:
    /// Missing relationships never establish that an Item is unaccounted.
    static func read(transaction: any Transaction, accountId: AccountID,
        principalId: PrincipalID, projectId: ProjectID,
        placementId: EntityID? = nil) throws -> [EntityID: ProjectItemAccountingRow] {
        let allowed = try transaction.get(sql: """
            SELECT EXISTS(SELECT 1 FROM spike_account_memberships
              WHERE account_id=? AND principal_id=? AND state='active' AND financial_access='full') AS allowed
            """, parameters: [accountId.rawValue, principalId.rawValue]) { try $0.getInt(name: "allowed") == 1 }
        guard allowed else { return [:] }
        let rows = try transaction.getAll(sql: """
            SELECT link.*, placement.item_id AS actual_item_id, placement.account_id AS actual_account_id,
              placement.project_id AS actual_project_id, placement.scope_kind, placement.space_id,
              project.client_id AS actual_client_id
            FROM item_client_payment_connections link
            LEFT JOIN spike_item_placements placement ON placement.id=link.placement_id
            LEFT JOIN spike_projects project ON project.id=link.project_id AND project.account_id=link.account_id
            WHERE link.project_id=? AND link.ended_at IS NULL AND placement.ended_at IS NULL
              AND (? IS NULL OR link.placement_id=?)
            ORDER BY link.placement_id, link.id
            """, parameters: [projectId.rawValue, placementId?.rawValue, placementId?.rawValue]) { cursor in
                let item = try cursor.getString(name: "item_id")
                let client = try cursor.getString(name: "client_id")
                guard try cursor.getString(name: "account_id") == accountId.rawValue,
                      try cursor.getStringOptional(name: "actual_account_id") == accountId.rawValue,
                      try cursor.getStringOptional(name: "actual_project_id") == projectId.rawValue,
                      try cursor.getStringOptional(name: "scope_kind") == "project",
                      try cursor.getStringOptional(name: "actual_item_id") == item,
                      try cursor.getStringOptional(name: "actual_client_id") == client,
                      try cursor.getString(name: "transaction_type") == "purchase",
                      try cursor.getString(name: "transaction_role") == "standalone" else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                let clientId = try ClientID(validating: client), itemId = try ItemID(validating: item)
                let connection = try ClientPaidPurchaseAccountingConnection(
                    id: ItemAccountingConnectionID(validating: cursor.getString(name: "id")),
                    accountId: accountId, projectId: projectId, clientId: clientId, itemId: itemId,
                    transactionId: TransactionID(validating: cursor.getString(name: "transaction_id")),
                    classification: .init(type: .purchase,
                        scope: .project(accountId: accountId, projectId: projectId, clientId: clientId), role: .standalone))
                return (try EntityID(validating: cursor.getString(name: "placement_id")),
                    try cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) }, connection)
            }
        var result = try Dictionary(grouping: rows, by: { $0.0 }).mapValues { rows -> ProjectItemAccountingRow in
            let first = rows[0]
            return try .init(evidence: .init(accountId: accountId, projectId: projectId,
                clientId: first.2.clientId, itemId: first.2.itemId, spaceId: first.1,
                clientPaidPurchases: rows.map { $0.2 }), relationshipAbsenceIsAuthoritative: false)
        }
        let charges = try transaction.getAll(sql: """
            SELECT charge.*, placement.account_id AS actual_account_id,
              placement.project_id AS actual_project_id, placement.item_id AS actual_item_id,
              placement.scope_kind, placement.space_id, project.client_id,
              typeof(charge.revision) AS revision_type,
              line.id AS line_id, line.account_id AS line_account, line.item_id AS line_item,
              line.category_id AS line_category, line.source_revision AS line_revision, line.source_kind AS line_kind,
              line.signed_amount_minor_units AS line_amount, line.currency AS line_currency,
              typeof(line.source_revision) AS line_revision_type,
              invoice.id AS invoice_id, invoice.account_id AS invoice_account,
              invoice.project_id AS invoice_project, invoice.client_id AS invoice_client, invoice.sealed
            FROM item_charge_occurrences charge
            LEFT JOIN spike_item_placements placement ON placement.id=charge.placement_id
            LEFT JOIN spike_projects project ON project.id=charge.project_id AND project.account_id=charge.account_id
            LEFT JOIN collected_invoice_lines line ON line.account_id=charge.account_id
              AND line.source_kind='item' AND line.source_id=charge.id
            LEFT JOIN collected_invoices invoice ON invoice.account_id=line.account_id AND invoice.id=line.invoice_id
            WHERE charge.project_id=? AND charge.withdrawn_at IS NULL AND placement.ended_at IS NULL
              AND (? IS NULL OR charge.placement_id=?)
            ORDER BY charge.placement_id, charge.id, line.id
            """, parameters: [projectId.rawValue, placementId?.rawValue, placementId?.rawValue]) { cursor in
              do {
                let item = try cursor.getString(name: "item_id")
                let client = try ClientID(validating: cursor.getString(name: "client_id"))
                let amountText = try cursor.getString(name: "amount_minor_units")
                let revision = try cursor.getInt64(name: "revision")
                let category = try BudgetCategoryID(validating: cursor.getString(name: "category_id"))
                let currency = try CurrencyCode(validating: cursor.getString(name: "currency"))
                guard try cursor.getString(name: "account_id") == accountId.rawValue,
                      try cursor.getStringOptional(name: "actual_account_id") == accountId.rawValue,
                      try cursor.getStringOptional(name: "actual_project_id") == projectId.rawValue,
                      try cursor.getStringOptional(name: "actual_item_id") == item,
                      try cursor.getStringOptional(name: "scope_kind") == "project",
                      let amount = Int64(amountText), amount > 0, String(amount) == amountText,
                      try cursor.getString(name: "revision_type") == "integer", revision > 0 else {
                    throw PropertyManagementReportLocalReadFailure.malformedEvidence
                }
                var phase = BillableItemOccurrencePhase.availableToInvoice
                if try cursor.getStringOptional(name: "line_id") != nil {
                    guard try cursor.getStringOptional(name: "line_account") == accountId.rawValue,
                          try cursor.getStringOptional(name: "line_kind") == "item",
                          try cursor.getStringOptional(name: "line_item") == item,
                          try cursor.getStringOptional(name: "line_category") == category.rawValue,
                          try cursor.getString(name: "line_revision_type") == "integer",
                          try cursor.getInt64Optional(name: "line_revision") == revision,
                          try cursor.getStringOptional(name: "line_amount") == amountText,
                          try cursor.getStringOptional(name: "line_currency") == currency.rawValue,
                          try cursor.getStringOptional(name: "invoice_account") == accountId.rawValue,
                          try cursor.getStringOptional(name: "invoice_project") == projectId.rawValue,
                          try cursor.getStringOptional(name: "invoice_client") == client.rawValue,
                          try cursor.getInt64Optional(name: "sealed") == 1,
                          let invoice = try cursor.getStringOptional(name: "invoice_id") else {
                        throw PropertyManagementReportLocalReadFailure.malformedEvidence
                    }
                    phase = .frozenPaid(invoiceId: try InvoiceID(validating: invoice))
                }
                return (try EntityID(validating: cursor.getString(name: "placement_id")), client,
                    try cursor.getStringOptional(name: "space_id").map { try SpaceID(validating: $0) },
                    BillableItemAccountingOccurrence(id: try .init(validating: cursor.getString(name: "id")),
                        accountId: accountId, projectId: projectId, itemId: try ItemID(validating: item),
                        polarity: .charge, phase: phase))
              } catch { throw PropertyManagementReportLocalReadFailure.malformedEvidence }
            }
        for (placement, entries) in Dictionary(grouping: charges, by: { $0.0 }) {
            // Exactly one current positive charge is allowed per placement. Duplicate
            // frozen references must also fail closed, not duplicate a paid fact.
            guard entries.count == 1 else { throw PropertyManagementReportLocalReadFailure.malformedEvidence }
            let entry = entries[0]
            result[placement] = try .init(evidence: .init(accountId: accountId, projectId: projectId,
                clientId: entry.1, itemId: entry.3.itemId, spaceId: entry.2,
                clientPaidPurchases: result[placement]?.evidence.clientPaidPurchases ?? [],
                billableOccurrences: [entry.3]), relationshipAbsenceIsAuthoritative: false)
        }
        return result
    }
}
