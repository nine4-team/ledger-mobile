import Foundation
import LedgerTargetCore
import PowerSync

struct DownloadedProjectItemsWatch: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func read(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
              asOf: Date = Date()) async throws -> DownloadedProjectItems {
        try await database.readTransaction { transaction in
            let placements = try CurrentItemPlacementLocalReader.readSnapshot(transaction: transaction,
                accountId: accountId, principalId: principalId, scope: .project(projectId))
            let accounting: ProjectItemAccountingSectionsSnapshot?
            do {
                _ = try PropertyManagementReportPowerSyncQuery.completedCheckpoint(transaction: transaction,
                    identity: .init(accountId: accountId, projectId: projectId))
                let client = try ClientSummaryPhysicalReportLocalReader.readClient(transaction: transaction,
                    accountId: accountId, principalId: principalId, projectId: projectId)
                guard case .known(let clientId, _, _) = client else {
                    throw ClientSummaryPhysicalReportLocalReadFailure.missingClientRelationship
                }
                let relationships = try ItemClientPaymentConnectionLocalReader.read(transaction: transaction,
                    accountId: accountId, principalId: principalId, projectId: projectId)
                let evidence = try placements.rows.map { placement in
                    if let row = relationships[placement.placementId] { return row.evidence }
                    return try ProjectItemAccountingEvidence(accountId: accountId, projectId: projectId,
                        clientId: clientId, itemId: placement.itemId, spaceId: placement.spaceId)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                let digest = try ProtectedArtifactSHA256.make(bytes: encoder.encode(evidence))
                accounting = try .init(accountId: accountId, projectId: projectId, clientId: clientId,
                    items: evidence, isCompleteForAccounting: false, quality: .ready,
                    localDataVersion: .init(validating: "project-items-\(digest.rawValue)"), asOf: asOf)
            } catch PropertyManagementReportFailure.incompleteReadiness { accounting = nil }
              catch let failure as ClientSummaryPhysicalReportLocalReadFailure {
                if failure == .accountUnavailable { throw failure }
                accounting = nil
            } catch PropertyManagementReportLocalReadFailure.malformedEvidence { accounting = nil }
              catch is ProjectItemAccountingSectionFailure { accounting = nil }
            return try .init(placements: placements, accounting: accounting)
        }
    }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             receive: @Sendable @escaping (DownloadedProjectItems) async -> Bool) async throws {
        let identity = PropertyManagementReportStreamIdentity(accountId: accountId, projectId: projectId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }, observe: {
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_clients WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_charge_occurrences WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='property_management_report')
                """, parameters: Array(repeating: accountId.rawValue, count: 10)) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let value = try await read(accountId: accountId, principalId: principalId, projectId: projectId)
                guard await receive(value) else { return }
            }
        })
    }
}
