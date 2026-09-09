import LedgerTargetCore
import PowerSync

enum ItemClientPaymentConnectionLocalReader {
    /// One project-wide read, not a query per Item. Absence remains unknown:
    /// business-paid evidence and restricted visibility are not complete yet.
    static func read(transaction: any Transaction, accountId: AccountID,
        principalId: PrincipalID, projectId: ProjectID) throws -> [EntityID: ProjectItemAccountingRow] {
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
            ORDER BY link.placement_id, link.id
            """, parameters: [projectId.rawValue]) { cursor in
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
        return try Dictionary(grouping: rows, by: { $0.0 }).mapValues { rows in
            let first = rows[0]
            return try .init(evidence: .init(accountId: accountId, projectId: projectId,
                clientId: first.2.clientId, itemId: first.2.itemId, spaceId: first.1,
                clientPaidPurchases: rows.map { $0.2 }), relationshipAbsenceIsAuthoritative: false)
        }
    }
}
