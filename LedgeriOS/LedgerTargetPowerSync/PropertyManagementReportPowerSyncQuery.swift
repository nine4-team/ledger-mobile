import Foundation
import LedgerTargetCore
import PowerSync

struct PropertyManagementReportStreamIdentity: SyncStreamDescription, Sendable {
    let name = "property_management_report"
    let parameters: JsonParam?

    init(accountId: AccountID, projectId: ProjectID) {
        parameters = ["account_id": .string(accountId.rawValue), "project_id": .string(projectId.rawValue)]
    }
}

/// Reads only previously completed scoped downloads. Opening a stream and owning
/// its lifetime belongs to the runtime, as does preventing use after account close.
/// This query never promotes global lastSyncedAt or an arbitrary local subset.
struct PropertyManagementReportPowerSyncQuery: Sendable {
    let database: any PowerSyncDatabaseProtocol

    func readDownloaded(accountId: AccountID, principalId: PrincipalID, projectId: ProjectID,
                        currency: CurrencyCode, asOf: ProtectedArtifactEpochMilliseconds) async throws
        -> PropertyManagementReportSnapshot {
        let identity = PropertyManagementReportStreamIdentity(accountId: accountId, projectId: projectId)
        return try await database.readTransaction { transaction in
            let inputs = try PropertyManagementReportLocalReader.read(transaction: transaction,
                accountId: accountId, principalId: principalId, projectId: projectId)
            let checkpoint = try Self.completedCheckpoint(transaction: transaction, identity: identity)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let version = try ProtectedArtifactSHA256.make(bytes: encoder.encode(inputs))
            let visibility = try ProtectedArtifactSHA256.make(bytes: encoder.encode(
                [accountId.rawValue, principalId.rawValue, projectId.rawValue, "physical-property-report-v1"]))
            return try PropertyManagementReportSnapshot.build(project: inputs.project, spaces: inputs.spaces,
                items: inputs.items, currency: currency, provenance: .init(accountId: accountId,
                    projectId: projectId, principalId: principalId,
                    visibilityScopeID: .init(validating: visibility.rawValue),
                    localDataVersion: .init(validating: "property-report-\(version.rawValue)"),
                    authorityVersion: .init(validating: "property-management-v1"), asOf: asOf,
                    readiness: .ready, lastSyncedAt: checkpoint))
        }
    }

    // The pinned SDK retains per-stream completion in microseconds. Read it
    // within the same SQLite transaction as membership and report rows so a
    // concurrent reads cannot mix metadata and rows from different transactions.
    // Actual core eviction/re-subscribe semantics require separate validation;
    // injected metadata tests alone are not proof of SDK download completeness.
    // No elapsed-time cutoff: approved offline use has no arbitrary expiry.
    static func completedCheckpoint(transaction: any Transaction,
                                    identity: PropertyManagementReportStreamIdentity) throws
        -> ProtectedArtifactEpochMilliseconds {
        let expected = identity.parameters.map(JsonValue.object) ?? .null
        let rows = try transaction.getAll(sql: """
            SELECT local_params, active, last_synced_at FROM ps_stream_subscriptions
            WHERE stream_name = ? ORDER BY id
            """, parameters: [identity.name]) { cursor in
                (try cursor.getString(name: "local_params"), try cursor.getInt(name: "active"),
                 try cursor.getInt64Optional(name: "last_synced_at"))
            }
        var exact: [(Int, Int64?)] = []
        for row in rows {
            let parameters = try JSONDecoder().decode(JsonValue.self, from: Data(row.0.utf8))
            if parameters == expected { exact.append((row.1, row.2)) }
        }
        guard exact.count == 1, exact[0].0 == 1, let microseconds = exact[0].1,
              microseconds >= 1_000 else { throw PropertyManagementReportFailure.incompleteReadiness }
        return try .init(validating: microseconds / 1_000)
    }
}
