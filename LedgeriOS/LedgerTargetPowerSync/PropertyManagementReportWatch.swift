import Foundation
import LedgerTargetCore
import PowerSync

struct PropertyManagementReportWatch: Sendable {
    let database: any PowerSyncDatabaseProtocol
    var now: @Sendable () -> Date = { Date() }

    func run(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
             currency: CurrencyCode,
             receive: @Sendable @escaping (PropertyManagementReportUpdate) async -> Bool) async throws {
        let identity = PropertyManagementReportStreamIdentity(accountId: accountId, projectId: projectId)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }, observe: {
            // PowerSync observes source-table changes, not result inequality.
            // Cheap EXISTS probes register every report dependency; each event
            // then reads the complete inputs/checkpoint in one new transaction.
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_projects WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_charge_occurrences WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='property_management_report')
                """, parameters: Array(repeating: accountId.rawValue, count: 9)) { try $0.getInt(index: 0) }
            for try await _ in changes {
                try Task.checkCancellation()
                let update: PropertyManagementReportUpdate
                do {
                    let milliseconds = now().timeIntervalSince1970 * 1000
                    guard milliseconds.isFinite, milliseconds >= 1, milliseconds < Double(Int64.max) else {
                        throw PropertyManagementReportFailure.incompleteReadiness
                    }
                    update = .ready(try await PropertyManagementReportPowerSyncQuery(database: database)
                        .readDownloaded(accountId: accountId, principalId: principalId, projectId: projectId,
                            currency: currency, asOf: .init(validating: Int64(milliseconds))))
                } catch PropertyManagementReportFailure.incompleteReadiness {
                    update = .incomplete
                } catch PropertyManagementReportLocalReadFailure.missingProject {
                    update = .incomplete
                } catch PropertyManagementReportLocalReadFailure.malformedEvidence {
                    update = .incomplete
                }
                guard await receive(update) else { return }
            }
        })
    }
}
