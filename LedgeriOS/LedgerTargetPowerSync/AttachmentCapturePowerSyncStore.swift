import Foundation
import LedgerTargetCore
import PowerSync

public enum AttachmentCapturePowerSyncTable {
    public static let queue = "local_attachment_durability_queue"
    public static let scopeBinding = "local_attachment_durability_scope_binding"
}

public enum AttachmentCapturePowerSyncSchema {
    public static let schema = Schema(
        Table(
            name: AttachmentCapturePowerSyncTable.queue,
            columns: [
                .text("environment"), .text("principal_id"), .text("account_id"),
                .text("parent_kind"), .text("parent_id"), .text("local_object_id"),
                .integer("captured_at_ms"), .integer("persisted_at_ms"),
                .integer("byte_count"), .text("content_sha256"),
                .text("receipt_fingerprint"), .text("receipt_json"), .text("state")
            ],
            indexes: [
                .ascending(
                    name: "attachment_queue_scope_order",
                    columns: [
                        "environment", "principal_id", "account_id",
                        "persisted_at_ms"
                    ]
                )
            ],
            localOnly: true
        ),
        Table(
            name: AttachmentCapturePowerSyncTable.scopeBinding,
            columns: [
                .text("environment"), .text("principal_id"), .text("account_id"),
                .text("binding_fingerprint")
            ],
            localOnly: true
        )
    )
}

public enum AttachmentCapturePowerSyncDatabaseFailure: Error, Equatable, Sendable {
    case invalidDatabasePath
}

public enum AttachmentCapturePowerSyncDatabaseFactory {
    public static func open(
        absolutePath: String,
        encryptionKey: LedgerPowerSyncEncryptionKey
    ) throws -> any PowerSyncDatabaseProtocol {
        guard absolutePath.hasPrefix("/"),
              URL(fileURLWithPath: absolutePath).lastPathComponent.hasSuffix(".sqlite") else {
            throw AttachmentCapturePowerSyncDatabaseFailure.invalidDatabasePath
        }
        return PowerSyncDatabase(
            schema: AttachmentCapturePowerSyncSchema.schema,
            dbFilename: absolutePath,
            initialStatements: ["PRAGMA key = \"x'\(encryptionKey.hexadecimal)'\""]
        )
    }
}

public enum AttachmentPendingState: String, Equatable, Sendable {
    case pending
    case missing
    case corrupt
}

public struct AttachmentPendingEvidence: Equatable, Sendable {
    public let attachmentIdentifier: String
    public let receipt: AttachmentLocalDurabilityReceipt?
    public let state: AttachmentPendingState
}

public struct AttachmentVerifiedUploadCandidate: Equatable, Sendable {
    public let receipt: AttachmentLocalDurabilityReceipt
    public let bytes: Data
}

public enum AttachmentStoreCheckpoint: String, CaseIterable, Sendable {
    case beforeQueueCommit
    case afterQueueCommit
    case beforeReceiptReturn
}

public enum AttachmentCapturePowerSyncStoreFailure: Error, Equatable, Sendable {
    case scopeMismatch
    case replayMismatch
    case invalidTimestamp
    case missingBytes
    case corruptBytes
    case malformedQueueEvidence
    case queuePersistenceFailed
    case mediaFailure(AttachmentLocalByteVaultFailure)
    case interrupted(AttachmentStoreCheckpoint)

    public var diagnosticCode: String {
        switch self {
        case .scopeMismatch: "attachment_store_scope_mismatch"
        case .replayMismatch: "attachment_store_replay_mismatch"
        case .invalidTimestamp: "attachment_store_timestamp_invalid"
        case .missingBytes: "attachment_store_bytes_missing"
        case .corruptBytes: "attachment_store_bytes_corrupt"
        case .malformedQueueEvidence: "attachment_store_queue_evidence_malformed"
        case .queuePersistenceFailed: "attachment_store_queue_persistence_failed"
        case .mediaFailure(let failure): failure.diagnosticCode
        case .interrupted(let checkpoint):
            "attachment_store_interrupted_\(checkpoint.rawValue)"
        }
    }
}

/// Local-only acceptance adapter. There is intentionally no API here to mark an
/// item uploaded, detach it, delete it, discard it, clean it up, or evict it.
public actor AttachmentCapturePowerSyncStore: AttachmentCaptureStoring {
    private let database: any PowerSyncDatabaseProtocol
    private let vault: AttachmentLocalByteVault
    private let scope: AttachmentDurabilityNamespaceScope
    private let now: @Sendable () -> Date
    private let fault: @Sendable (AttachmentStoreCheckpoint) throws -> Void
    private var inFlight: [String: InFlightCapture] = [:]

    public init(
        database: any PowerSyncDatabaseProtocol,
        vault: AttachmentLocalByteVault,
        scope: AttachmentDurabilityNamespaceScope,
        now: @Sendable @escaping () -> Date = Date.init,
        fault: @Sendable @escaping (AttachmentStoreCheckpoint) throws -> Void = { _ in }
    ) {
        self.database = database
        self.vault = vault
        self.scope = scope
        self.now = now
        self.fault = fault
    }

    public func enqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        guard scope.contains(capture.scope) else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        try await ensureScopeBinding()
        let identity = CaptureIdentity(capture)
        if let existing = inFlight[capture.attachmentId.rawValue] {
            guard existing.identity == identity else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            return try await existing.task.value
        }
        let task = Task { try await self.performEnqueue(capture) }
        inFlight[capture.attachmentId.rawValue] = InFlightCapture(
            identity: identity,
            task: task
        )
        do {
            let receipt = try await task.value
            inFlight[capture.attachmentId.rawValue] = nil
            return receipt
        } catch {
            inFlight[capture.attachmentId.rawValue] = nil
            throw error
        }
    }

    private func performEnqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {

        if let existing = try await existingRow(attachmentIdentifier: capture.attachmentId.rawValue) {
            guard existing.environment == scope.environment.rawValue,
                  existing.principalID == scope.principalId.rawValue,
                  existing.accountID == scope.accountId.rawValue else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            guard let record = existing.validatedRecord,
                  record.receipt.attachmentId == capture.attachmentId,
                  record.receipt.scope == capture.scope,
                  record.receipt.capturedAt == capture.capturedAt,
                  record.receipt.byteCount == capture.byteCount,
                  record.receipt.contentSHA256 == capture.contentSHA256 else {
                try? await setState(.corrupt, rowID: existing.id)
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            let bytes = try await verifiedBytes(for: record, rowID: existing.id)
            guard bytes == capture.bytes else {
                try? await setState(.corrupt, rowID: existing.id)
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            try invoke(.beforeReceiptReturn)
            return record.receipt
        }

        let persistedAt = try timestamp(now())
        let persistedEvidence: AttachmentPersistedLocalObjectEvidence
        do {
            persistedEvidence = try await vault.persist(capture, persistedAt: persistedAt)
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw translate(failure)
        }
        let receipt = try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: persistedEvidence
        )
        let receiptJSON = String(
            decoding: try OperationContractCodec.encode(receipt),
            as: UTF8.self
        )

        do {
            try invoke(.beforeQueueCommit)
            _ = try await database.execute(
                sql: """
                INSERT INTO \(AttachmentCapturePowerSyncTable.queue) (
                  id, environment, principal_id, account_id, parent_kind, parent_id,
                  local_object_id, captured_at_ms, persisted_at_ms, byte_count,
                  content_sha256, receipt_fingerprint, receipt_json, state
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
                """,
                parameters: [
                    receipt.attachmentId.rawValue,
                    receipt.scope.environment.rawValue,
                    receipt.scope.principalId.rawValue,
                    receipt.scope.accountId.rawValue,
                    receipt.scope.parent.kind.rawValue,
                    receipt.scope.parent.id.rawValue,
                    receipt.localObjectId.rawValue,
                    receipt.capturedAt.rawValue,
                    receipt.persistedAt.rawValue,
                    Int64(receipt.byteCount),
                    receipt.contentSHA256.rawValue,
                    receipt.fingerprint.rawValue,
                    receiptJSON
                ]
            )
            try invoke(.afterQueueCommit)
        } catch let failure as AttachmentCapturePowerSyncStoreFailure {
            throw failure
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
        }

        guard let committed = try await existingRow(
            attachmentIdentifier: receipt.attachmentId.rawValue
        ), let record = committed.validatedRecord,
           record.receipt == receipt else {
            throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
        }
        let verified = try await verifiedBytes(for: record, rowID: committed.id)
        guard verified == capture.bytes else {
            try? await setState(.corrupt, rowID: committed.id)
            throw AttachmentCapturePowerSyncStoreFailure.corruptBytes
        }
        try invoke(.beforeReceiptReturn)
        return receipt
    }

    public func pendingCount() async throws -> Int64 {
        try await ensureScopeBinding()
        return try await database.get(
            "SELECT count(*) AS count FROM \(AttachmentCapturePowerSyncTable.queue)"
        ) { cursor in
            try cursor.getInt64(name: "count")
        }
    }

    public func pendingEvidence() async throws -> [AttachmentPendingEvidence] {
        try await ensureScopeBinding()
        let rows = try await scopedRows()
        var result: [AttachmentPendingEvidence] = []
        result.reserveCapacity(rows.count)
        for row in rows {
            guard let record = row.validatedRecord else {
                try? await setState(.corrupt, rowID: row.id)
                result.append(
                    AttachmentPendingEvidence(
                        attachmentIdentifier: row.id,
                        receipt: nil,
                        state: .corrupt
                    )
                )
                continue
            }
            let state = await currentState(for: record)
            if state != row.state { try? await setState(state, rowID: row.id) }
            result.append(
                AttachmentPendingEvidence(
                    attachmentIdentifier: row.id,
                    receipt: record.receipt,
                    state: state
                )
            )
        }
        return result
    }

    public func nextVerifiedCandidate() async throws -> AttachmentVerifiedUploadCandidate? {
        try await ensureScopeBinding()
        for row in try await scopedRows() {
            guard let record = row.validatedRecord else {
                try? await setState(.corrupt, rowID: row.id)
                continue
            }
            do {
                let bytes = try await vault.verifiedBytes(for: record.persistedEvidence)
                if row.state != .pending { try? await setState(.pending, rowID: row.id) }
                return AttachmentVerifiedUploadCandidate(receipt: record.receipt, bytes: bytes)
            } catch let failure as AttachmentLocalByteVaultFailure {
                try? await setState(state(for: failure), rowID: row.id)
            }
        }
        return nil
    }

    public func orphanInventory() async throws -> [AttachmentVaultOrphan] {
        try await ensureScopeBinding()
        let referenced = Set(try await scopedRows().compactMap { row in
            row.validatedRecord?.receipt.localObjectId
        })
        return try await vault.orphanInventory(referencedObjectIDs: referenced)
    }

    private func timestamp(_ date: Date) throws -> AttachmentEpochMilliseconds {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds <= Double(Int64.max) else {
            throw AttachmentCapturePowerSyncStoreFailure.invalidTimestamp
        }
        return try AttachmentEpochMilliseconds(
            validating: Int64(milliseconds.rounded(.towardZero))
        )
    }

    private func existingRow(attachmentIdentifier: String) async throws -> QueueRow? {
        do {
            return try await database.getOptional(
                sql: "SELECT * FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id = ?",
                parameters: [attachmentIdentifier],
                mapper: QueueRow.init(cursor:)
            )
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
        }
    }

    private func scopedRows() async throws -> [QueueRow] {
        do {
            return try await database.getAll(
                sql: """
                SELECT * FROM \(AttachmentCapturePowerSyncTable.queue)
                ORDER BY persisted_at_ms ASC, id ASC
                """,
                parameters: nil,
                mapper: QueueRow.init(cursor:)
            )
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
        }
    }

    private func verifiedBytes(for record: QueueRecord, rowID: String) async throws -> Data {
        do {
            return try await vault.verifiedBytes(for: record.persistedEvidence)
        } catch let failure as AttachmentLocalByteVaultFailure {
            try? await setState(state(for: failure), rowID: rowID)
            throw translate(failure)
        }
    }

    private func currentState(for record: QueueRecord) async -> AttachmentPendingState {
        do {
            _ = try await vault.verifiedBytes(for: record.persistedEvidence)
            return .pending
        } catch let failure as AttachmentLocalByteVaultFailure {
            return state(for: failure)
        } catch {
            return .corrupt
        }
    }

    private func state(for failure: AttachmentLocalByteVaultFailure) -> AttachmentPendingState {
        failure == .missingObject ? .missing : .corrupt
    }

    private func setState(_ state: AttachmentPendingState, rowID: String) async throws {
        _ = try await database.execute(
            sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET state = ? WHERE id = ?",
            parameters: [state.rawValue, rowID]
        )
    }

    private func ensureScopeBinding() async throws {
        do {
            let expected = ScopeBindingRow(
                environment: scope.environment.rawValue,
                principalID: scope.principalId.rawValue,
                accountID: scope.accountId.rawValue,
                fingerprint: scope.databaseBindingFingerprint
            )
            try await database.writeTransaction { transaction in
                var binding = try transaction.getOptional(
                    sql: """
                    SELECT environment, principal_id, account_id, binding_fingerprint
                    FROM \(AttachmentCapturePowerSyncTable.scopeBinding) WHERE id = 'scope'
                    """,
                    parameters: nil
                ) { cursor in
                    ScopeBindingRow(
                        environment: try cursor.getStringOptional(name: "environment"),
                        principalID: try cursor.getStringOptional(name: "principal_id"),
                        accountID: try cursor.getStringOptional(name: "account_id"),
                        fingerprint: try cursor.getStringOptional(name: "binding_fingerprint")
                    )
                }
                if binding == nil {
                    let queued = try transaction.get(
                        sql: "SELECT count(*) AS count FROM \(AttachmentCapturePowerSyncTable.queue)",
                        parameters: nil
                    ) { try $0.getInt64(name: "count") }
                    guard queued == 0 else {
                        throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
                    }
                    _ = try transaction.execute(
                        sql: """
                        INSERT INTO \(AttachmentCapturePowerSyncTable.scopeBinding) (
                          id, environment, principal_id, account_id, binding_fingerprint
                        ) VALUES ('scope', ?, ?, ?, ?)
                        """,
                        parameters: [
                            expected.environment, expected.principalID,
                            expected.accountID, expected.fingerprint
                        ]
                    )
                    binding = expected
                }
                guard binding == expected else {
                    throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
                }
            }
        } catch let failure as AttachmentCapturePowerSyncStoreFailure {
            throw failure
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
        }
    }

    private func invoke(_ checkpoint: AttachmentStoreCheckpoint) throws {
        do {
            try fault(checkpoint)
        } catch let failure as AttachmentCapturePowerSyncStoreFailure {
            throw failure
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.interrupted(checkpoint)
        }
    }

    private func translate(
        _ failure: AttachmentLocalByteVaultFailure
    ) -> AttachmentCapturePowerSyncStoreFailure {
        switch failure {
        case .scopeMismatch:
            .scopeMismatch
        case .missingObject:
            .missingBytes
        case .invalidLocalObjectIdentity, .linkSubstitution, .corruptObject:
            .corruptBytes
        default:
            .mediaFailure(failure)
        }
    }
}

private struct CaptureIdentity: Equatable, Sendable {
    let attachmentID: AttachmentID
    let scope: AttachmentCaptureScope
    let capturedAt: AttachmentEpochMilliseconds
    let bytes: Data

    init(_ capture: LocalAttachmentCapture) {
        attachmentID = capture.attachmentId
        scope = capture.scope
        capturedAt = capture.capturedAt
        bytes = capture.bytes
    }
}

private struct ScopeBindingRow: Equatable, Sendable {
    let environment: String?
    let principalID: String?
    let accountID: String?
    let fingerprint: String?
}

private struct InFlightCapture: Sendable {
    let identity: CaptureIdentity
    let task: Task<AttachmentLocalDurabilityReceipt, Error>
}

private struct QueueRecord: Sendable {
    let receipt: AttachmentLocalDurabilityReceipt

    var persistedEvidence: AttachmentPersistedLocalObjectEvidence {
        get throws {
            try AttachmentPersistedLocalObjectEvidence(
                attachmentId: receipt.attachmentId,
                scope: receipt.scope,
                localObjectId: receipt.localObjectId,
                byteCount: receipt.byteCount,
                contentSHA256: receipt.contentSHA256,
                persistedAt: receipt.persistedAt
            )
        }
    }
}

private struct QueueRow: Sendable {
    let id: String
    let environment: String?
    let principalID: String?
    let accountID: String?
    let parentKind: String?
    let parentID: String?
    let localObjectID: String?
    let capturedAt: Int64?
    let persistedAt: Int64?
    let byteCount: Int64?
    let contentSHA256: String?
    let receiptFingerprint: String?
    let receiptJSON: String?
    let rawState: String?

    var state: AttachmentPendingState {
        rawState.flatMap(AttachmentPendingState.init(rawValue:)) ?? .corrupt
    }

    init(cursor: any SqlCursor) throws {
        id = try cursor.getString(name: "id")
        environment = try cursor.getStringOptional(name: "environment")
        principalID = try cursor.getStringOptional(name: "principal_id")
        accountID = try cursor.getStringOptional(name: "account_id")
        parentKind = try cursor.getStringOptional(name: "parent_kind")
        parentID = try cursor.getStringOptional(name: "parent_id")
        localObjectID = try cursor.getStringOptional(name: "local_object_id")
        capturedAt = try cursor.getInt64Optional(name: "captured_at_ms")
        persistedAt = try cursor.getInt64Optional(name: "persisted_at_ms")
        byteCount = try cursor.getInt64Optional(name: "byte_count")
        contentSHA256 = try cursor.getStringOptional(name: "content_sha256")
        receiptFingerprint = try cursor.getStringOptional(name: "receipt_fingerprint")
        receiptJSON = try cursor.getStringOptional(name: "receipt_json")
        rawState = try cursor.getStringOptional(name: "state")
    }

    var validatedRecord: QueueRecord? {
        guard let environment,
              let principalID,
              let accountID,
              let parentKind,
              let parentID,
              let localObjectID,
              let capturedAt,
              let persistedAt,
              let byteCount,
              let contentSHA256,
              let receiptFingerprint,
              let receiptJSON,
              let rawState,
              let data = receiptJSON.data(using: .utf8),
              let receipt = try? OperationContractCodec.decode(
                  AttachmentLocalDurabilityReceipt.self,
                  from: data
              ),
              byteCount > 0,
              receipt.attachmentId.rawValue == id,
              receipt.scope.environment.rawValue == environment,
              receipt.scope.principalId.rawValue == principalID,
              receipt.scope.accountId.rawValue == accountID,
              receipt.scope.parent.kind.rawValue == parentKind,
              receipt.scope.parent.id.rawValue == parentID,
              receipt.localObjectId.rawValue == localObjectID,
              receipt.capturedAt.rawValue == capturedAt,
              receipt.persistedAt.rawValue == persistedAt,
              receipt.byteCount == UInt64(byteCount),
              receipt.contentSHA256.rawValue == contentSHA256,
              receipt.fingerprint.rawValue == receiptFingerprint,
              AttachmentPendingState(rawValue: rawState) != nil else {
            return nil
        }
        return QueueRecord(receipt: receipt)
    }
}
