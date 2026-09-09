import Foundation
import LedgerTargetCore
import PowerSync

struct ClientSummaryPhysicalReportWatch: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
        receive: @Sendable @escaping (ClientSummaryPhysicalReportUpdate) async -> Bool) async throws {
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
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_project_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='property_management_report')
                """, parameters: Array(repeating: accountId.rawValue, count: 9)) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let update: ClientSummaryPhysicalReportUpdate
                do {
                    update = .ready(try await PropertyManagementReportPowerSyncQuery(database: database)
                        .readDownloadedClientSummary(accountId: accountId, principalId: principalId,
                            projectId: projectId, asOf: .init(validating: Int64(Date().timeIntervalSince1970 * 1000))))
                } catch PropertyManagementReportFailure.incompleteReadiness {
                    update = .incomplete
                } catch PropertyManagementReportLocalReadFailure.missingProject {
                    update = .incomplete
                } catch PropertyManagementReportLocalReadFailure.malformedEvidence {
                    update = .incomplete
                } catch ClientSummaryPhysicalReportLocalReadFailure.missingClientRelationship {
                    update = .incomplete
                } catch ClientSummaryPhysicalReportLocalReadFailure.malformedClient {
                    update = .incomplete
                } catch ClientSummaryPhysicalReportLocalReadFailure.malformedItem {
                    update = .incomplete
                } catch ClientSummaryPhysicalReportLocalReadFailure.missingSpace {
                    update = .incomplete
                }
                guard await receive(update) else { return }
            }
        })
    }
}
