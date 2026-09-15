import Foundation
import LedgerTargetCore
import PowerSync

/// Byte cache only. Parent reference authorization belongs to the calling runtime
/// and must be checked before and after awaiting cached or downloaded bytes.
protocol DownloadedImageCaching: Sendable {
    // Compatibility method names; PDFs use the same verified byte path. The
    // caller must still authorize its Transaction reference, not an Item/logo.
    func cachedDownloadedImage(_ reference: DownloadedMediaObjectReference) async throws -> Data?
    func cacheDownloadedImage(_ bytes: Data, reference: DownloadedMediaObjectReference) async throws
}

/// Shared by Item images and Transaction attachments. Authorization belongs to
/// their live parent relationship, not to the fact that these bytes are cached.
func loadAuthorizedDownloadedMedia(_ reference: DownloadedMediaObjectReference,
    cache: any DownloadedImageCaching,
    download: (@Sendable (DownloadedMediaObjectReference) async throws -> Data)?,
    authorize: @Sendable () async throws -> Void) async throws -> Data? {
    try await authorize()
    var bytes: Data?
    do { bytes = try await cache.cachedDownloadedImage(reference) }
    catch AttachmentLocalByteVaultFailure.missingObject { }
    catch AttachmentLocalByteVaultFailure.corruptObject { }
    try await authorize()
    if bytes == nil, let download {
        let downloaded = try await download(reference)
        try await authorize()
        // The shared cache independently verifies length/hash, including when
        // an injected transport does not. Never admit a stale reference.
        try await cache.cacheDownloadedImage(downloaded, reference: reference)
        try await authorize()
        bytes = downloaded
    }
    try await authorize()
    return bytes
}

extension AccountBusinessLogoReference {
    init(downloadedImage reference: DownloadedImageObjectReference) throws {
        try self.init(accountId: reference.accountId, attachmentId: reference.attachmentId.rawValue,
            sha256: reference.contentSHA256.rawValue, byteCount: String(reference.byteCount),
            mediaType: reference.mediaType, storagePath: reference.storagePath)
    }

    var downloadedImageReference: DownloadedImageObjectReference {
        get throws {
            try DownloadedImageObjectReference(accountId: accountId,
                attachmentId: attachmentId.rawValue, sha256: contentSHA256.rawValue,
                byteCount: String(byteCount), mediaType: mediaType, storagePath: storagePath)
        }
    }
}

extension AttachmentCapturePowerSyncStore: DownloadedImageCaching {}

public enum AttachmentCapturePowerSyncTable {
    public static let queue = "local_attachment_durability_queue"
    public static let scopeBinding = "local_attachment_durability_scope_binding"
    // Preserve the existing local table and encrypted evidence on upgrade. It now
    // caches authorized image objects shared by Account profile and Item readers.
    public static let downloadedLogos = "local_downloaded_account_logos"
}

public enum AttachmentCapturePowerSyncSchema {
    public static let schema = Schema(
        Table(
            name: AttachmentCapturePowerSyncTable.downloadedLogos,
            columns: [.text("evidence_json")],
            localOnly: true
        ),
        Table(
            name: AttachmentCapturePowerSyncTable.queue,
            columns: [
                .text("environment"), .text("principal_id"), .text("account_id"),
                .text("parent_kind"), .text("parent_id"), .text("local_object_id"),
                .integer("captured_at_ms"), .integer("persisted_at_ms"),
                .integer("byte_count"), .text("content_sha256"),
                .text("receipt_fingerprint"), .text("receipt_json"), .text("state"),
                .text("upload_progress_json")
            ],
            indexes: [
                .ascending(
                    name: "attachment_queue_scope_order",
                    columns: [
                        "environment", "principal_id", "account_id",
                        "persisted_at_ms"
                    ]
                ),
                .ascending(name: "attachment_queue_parent", columns: ["parent_kind", "parent_id", "persisted_at_ms"])
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

enum AttachmentCapturePowerSyncDatabaseFailure: Error, Equatable, Sendable {
    case invalidDatabasePath
}

enum AttachmentCapturePowerSyncDatabaseFactory {
    static func open(
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

public struct AttachmentPendingWorkQueueEvidence: Equatable, Sendable {
    public let receipt: AttachmentLocalDurabilityReceipt
    public let state: AttachmentPendingState

    public init(
        receipt: AttachmentLocalDurabilityReceipt,
        state: AttachmentPendingState
    ) {
        self.receipt = receipt
        self.state = state
    }
}

public struct AttachmentPendingWorkObservation: Equatable, Sendable {
    public let queue: [AttachmentPendingWorkQueueEvidence]
    public let orphans: [AttachmentVaultOrphan]

    public init(
        queue: [AttachmentPendingWorkQueueEvidence],
        orphans: [AttachmentVaultOrphan]
    ) {
        self.queue = queue.sorted {
            ($0.receipt.persistedAt.rawValue, $0.receipt.attachmentId.rawValue) <
                ($1.receipt.persistedAt.rawValue, $1.receipt.attachmentId.rawValue)
        }
        self.orphans = orphans.sorted {
            ($0.kind.rawValue, $0.opaqueIdentity) <
                ($1.kind.rawValue, $1.opaqueIdentity)
        }
    }
}

public protocol AttachmentPendingWorkObserving: Sendable {
    func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation
}

public struct AttachmentVerifiedUploadCandidate: Equatable, Sendable {
    public let receipt: AttachmentLocalDurabilityReceipt
    public let bytes: Data
}

/// Local transport evidence only; even an applied result cannot authorize queue
/// deletion until the current synced parent reference is independently observed.
struct AttachmentUploadProgress: Codable, Equatable, Sendable {
    var checkpoint: TransactionAttachmentUploadCheckpoint?
    var publication: TransactionAttachmentPublication?
    var expense: ExpenseReceiptUploadProgress? = nil
}

struct ExpenseReceiptUploadProgress: Codable, Equatable, Sendable {
    let projectId: EntityID
    let publication: ExpenseAttachmentPublication
}

typealias ExpenseAttachmentPublisher = @Sendable (
    AttachmentVerifiedUploadCandidate, TransactionAttachmentUploadCheckpoint?,
    @escaping SupabaseTransactionAttachmentUpload.CheckpointHandler
) async throws -> ExpenseAttachmentPublication

typealias TransactionAttachmentPublisher = @Sendable (
    AttachmentVerifiedUploadCandidate, TransactionAttachmentUploadCheckpoint?,
    @escaping SupabaseTransactionAttachmentUpload.CheckpointHandler
) async throws -> TransactionAttachmentPublication

public enum AttachmentStoreCheckpoint: String, CaseIterable, Sendable {
    case beforeQueueCommit
    case afterQueueCommit
    case beforeReceiptReturn
}

public enum AttachmentCapturePowerSyncStoreFailure: Error, Equatable, Sendable {
    case scopeMismatch
    case replayMismatch
    case attachmentBusy
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
        case .attachmentBusy: "attachment_store_attachment_busy"
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

/// Protected capture/cache ownership and upload progress. Queue drainage requires
/// publication plus synced reference evidence; no detach, discard or byte eviction.
actor AttachmentCapturePowerSyncStore:
    AttachmentCaptureStoring,
    AttachmentPendingWorkObserving,
    AttachmentLocalByteResolving
{
    private let database: any PowerSyncDatabaseProtocol
    private let vault: AttachmentLocalByteVault
    private let scope: AttachmentDurabilityNamespaceScope
    private let now: @Sendable () -> Date
    private let fault: @Sendable (AttachmentStoreCheckpoint) throws -> Void
    private let resolutionRead:
        @Sendable (AttachmentPersistedLocalObjectEvidence) async throws -> Data
    private let resolutionDatabaseAccessCheckpoint: @Sendable () async throws -> Void
    private let resolutionLookupCheckpoint: @Sendable () async throws -> Void
    private let enqueueCommitCheckpoint: @Sendable () async throws -> Void
    private var inFlight: [String: InFlightCapture] = [:]
    private var cachingAttachmentIDs: Set<String> = []
    private var publishingAttachmentIDs: Set<String> = []

    init(
        database: any PowerSyncDatabaseProtocol,
        vault: AttachmentLocalByteVault,
        scope: AttachmentDurabilityNamespaceScope,
        now: @Sendable @escaping () -> Date = Date.init,
        fault: @Sendable @escaping (AttachmentStoreCheckpoint) throws -> Void = { _ in },
        resolutionRead:
            (@Sendable (AttachmentPersistedLocalObjectEvidence) async throws -> Data)? = nil,
        resolutionDatabaseAccessCheckpoint: @Sendable @escaping () async throws -> Void = {},
        resolutionLookupCheckpoint: @Sendable @escaping () async throws -> Void = {},
        enqueueCommitCheckpoint: @Sendable @escaping () async throws -> Void = {}
    ) {
        self.database = database
        self.vault = vault
        self.scope = scope
        self.now = now
        self.fault = fault
        self.resolutionRead = resolutionRead ?? { evidence in
            try await vault.verifiedBytes(for: evidence)
        }
        self.resolutionDatabaseAccessCheckpoint = resolutionDatabaseAccessCheckpoint
        self.resolutionLookupCheckpoint = resolutionLookupCheckpoint
        self.enqueueCommitCheckpoint = enqueueCommitCheckpoint
    }

    public func enqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        try await enqueue(capture, authorize: {})
    }

    func enqueue(_ capture: LocalAttachmentCapture,
        authorize: @Sendable @escaping () async throws -> Void
    ) async throws -> AttachmentLocalDurabilityReceipt {
        guard scope.contains(capture.scope) else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        try await ensureScopeBinding()
        try await authorize()
        let identity = CaptureIdentity(capture)
        guard !cachingAttachmentIDs.contains(capture.attachmentId.rawValue) else {
            throw AttachmentCapturePowerSyncStoreFailure.attachmentBusy
        }
        if let existing = inFlight[capture.attachmentId.rawValue] {
            guard existing.identity == identity else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            return try await existing.task.value
        }
        let task = Task { try await self.performEnqueue(capture, authorize: authorize) }
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
        _ capture: LocalAttachmentCapture,
        authorize: @Sendable () async throws -> Void
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
                  record.receipt.metadata == capture.metadata,
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

        try await enqueueCommitCheckpoint()
        try await authorize()
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

    /// Metadata-only query for capacity and local pending relationships. Do not
    /// decrypt every queued original or perform orphan reconciliation for an Add.
    func pendingCaptureReceipts(parent: LedgerEntityReference) async throws -> [AttachmentLocalDurabilityReceipt] {
        try await ensureScopeBinding()
        let rows = try await database.getAll(sql: """
            SELECT * FROM \(AttachmentCapturePowerSyncTable.queue)
            WHERE parent_kind=? AND parent_id=? ORDER BY persisted_at_ms,id
            """, parameters: [parent.kind.rawValue, parent.id.rawValue], mapper: QueueRow.init(cursor:))
        return try rows.map { row in
            guard let record = row.validatedRecord, scope.contains(record.receipt.scope),
                  record.receipt.scope.parent == parent else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            return record.receipt
        }
    }

    func pendingTransactionUploads() async throws -> [AttachmentLocalDurabilityReceipt] {
        try await ensureScopeBinding()
        return try await scopedRows().compactMap { row in
            guard row.parentKind == "transaction" else { return nil }
            guard let record = row.validatedRecord, scope.contains(record.receipt.scope) else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            if case .rejected = try row.uploadProgress?.publication { return nil }
            return record.receipt // Applied entries still need authoritative readback.
        }
    }

    func pendingExpenseReconciliations() async throws -> [(AttachmentLocalDurabilityReceipt, EntityID)] {
        try await ensureScopeBinding()
        return try await scopedRows().compactMap { row in
            guard row.parentKind == "expense", let record = row.validatedRecord,
                  let progress = try row.uploadProgress?.expense, progress.publication == .verified else { return nil }
            return (record.receipt, progress.projectId)
        }
    }

    func pendingCaptureRejections(parent: LedgerEntityReference) async throws -> [AttachmentID: String] {
        try await ensureScopeBinding()
        let rows = try await database.getAll(sql: """
            SELECT * FROM \(AttachmentCapturePowerSyncTable.queue) WHERE parent_kind=? AND parent_id=?
            """, parameters: [parent.kind.rawValue, parent.id.rawValue], mapper: QueueRow.init(cursor:))
        var rejections: [AttachmentID: String] = [:]
        for row in rows {
            guard let record = row.validatedRecord, scope.contains(record.receipt.scope),
                  record.receipt.scope.parent == parent else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            if case let .rejected(code) = try row.uploadProgress?.publication {
                rejections[record.receipt.attachmentId] = code
            }
        }
        return rejections
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
            if let publication = try row.uploadProgress?.publication, publication != .incomplete {
                continue // Retain applied/rejected bytes, but do not upload them again.
            }
            if try row.uploadProgress?.expense?.publication == .verified { continue }
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

    func publishTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        publish: TransactionAttachmentPublisher) async throws -> TransactionAttachmentPublication {
        guard receipt.scope.parent.kind == .transaction else {
            throw SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt
        }
        guard publishingAttachmentIDs.insert(receipt.attachmentId.rawValue).inserted else {
            throw AttachmentCapturePowerSyncStoreFailure.attachmentBusy
        }
        defer { publishingAttachmentIDs.remove(receipt.attachmentId.rawValue) }
        let progress = try await uploadProgress(for: receipt)
        if let result = progress?.publication, result != .incomplete { return result }
        let bytes = try await resolveLocalAttachmentBytes(for: receipt)
        let result = try await publish(.init(receipt: receipt, bytes: bytes), progress?.checkpoint) { checkpoint in
            try await self.saveUploadProgress(.init(checkpoint: checkpoint, publication: nil), for: receipt)
        }
        let latest = try await uploadProgress(for: receipt)
        try await saveUploadProgress(.init(checkpoint: latest?.checkpoint, publication: result), for: receipt)
        return result
    }

    func verifiedExpenseReceipts(for command: CreateExpenseCommand) async throws -> Set<AttachmentID> {
        let e = command.envelope
        guard e.accountId == scope.accountId, e.actorPrincipalId == scope.principalId else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        try await ensureScopeBinding()
        var verified: Set<AttachmentID> = []
        for id in e.payload.receiptAttachmentIds {
            guard let row = try await existingRow(attachmentIdentifier: id.rawValue) else { continue }
            guard let record = row.validatedRecord, scope.contains(record.receipt.scope),
                  record.receipt.scope.parent.kind == .expense,
                  record.receipt.scope.parent.id.rawValue == e.payload.expenseId.rawValue else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            if let progress = try row.uploadProgress?.expense,
               progress.projectId.rawValue == e.payload.projectId.rawValue, progress.publication == .verified {
                verified.insert(id)
            }
        }
        return verified
    }

    func publishExpenseAttachment(_ receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID,
        publish: ExpenseAttachmentPublisher) async throws -> ExpenseAttachmentPublication {
        guard receipt.scope.parent.kind == .expense else {
            throw SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt
        }
        guard publishingAttachmentIDs.insert(receipt.attachmentId.rawValue).inserted else {
            throw AttachmentCapturePowerSyncStoreFailure.attachmentBusy
        }
        defer { publishingAttachmentIDs.remove(receipt.attachmentId.rawValue) }
        let progress = try await uploadProgress(for: receipt)
        guard progress?.publication == nil,
              progress?.expense == nil || progress?.expense?.projectId == projectId else {
            throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
        }
        if progress?.expense?.publication == .verified { return .verified }
        // Persist project binding before network admission, including interruptions
        // before the first TUS checkpoint. The same Expense cannot silently move.
        try await saveUploadProgress(.init(checkpoint: progress?.checkpoint, publication: nil,
            expense: .init(projectId: projectId, publication: .incomplete)), for: receipt)
        let bytes = try await resolveLocalAttachmentBytes(for: receipt)
        let result = try await publish(.init(receipt: receipt, bytes: bytes), progress?.checkpoint) { checkpoint in
            try await self.saveUploadProgress(.init(checkpoint: checkpoint, publication: nil,
                expense: .init(projectId: projectId, publication: .incomplete)), for: receipt)
        }
        let latest = try await uploadProgress(for: receipt)
        try await saveUploadProgress(.init(checkpoint: latest?.checkpoint, publication: nil,
            expense: .init(projectId: projectId, publication: result)), for: receipt)
        return result
    }

    func uploadProgress(for receipt: AttachmentLocalDurabilityReceipt) async throws -> AttachmentUploadProgress? {
        guard scope.contains(receipt.scope) else { throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch }
        try await ensureScopeBinding()
        guard let row = try await existingRow(attachmentIdentifier: receipt.attachmentId.rawValue),
              row.validatedRecord?.receipt == receipt else {
            throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
        }
        return try row.uploadProgress
    }

    /// Caller supplies an authorized synced-only catalog, never its pending overlay.
    /// Move ownership of the SAME protected file in one local transaction; no
    /// deletion, re-encryption or window where the bytes become an orphan.
    func reconcileTransactionAttachment(_ receipt: AttachmentLocalDurabilityReceipt,
        catalog: DownloadedTransactionAttachments) async throws -> Bool {
        let progress = try await uploadProgress(for: receipt)
        guard case let .applied(revision, _) = progress?.publication,
              receipt.scope.parent.kind == .transaction,
              catalog.scope.accountId == receipt.scope.accountId,
              catalog.transactionId.rawValue == receipt.scope.parent.id.rawValue,
              catalog.section == receipt.metadata?.transactionSection,
              catalog.isComplete, let currentRevision = catalog.revision, currentRevision >= revision,
              let attachment = catalog.attachments.first(where: { $0.id.rawValue == receipt.attachmentId.rawValue }),
              attachment.localReceipt == nil,
              attachment.object.attachmentId == receipt.attachmentId,
              attachment.object.contentSHA256 == receipt.contentSHA256,
              UInt64(attachment.object.byteCount) == receipt.byteCount,
              attachment.object.mediaType == receipt.metadata?.mediaType else { return false }
        return try await retainReconciledBytes(receipt, progress: progress)
    }

    func reconcileExpenseAttachment(_ receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID,
                                    object: DownloadedMediaObjectReference) async throws -> Bool {
        let progress = try await uploadProgress(for: receipt)
        guard receipt.scope.parent.kind == .expense, progress?.expense?.projectId == projectId,
              progress?.expense?.publication == .verified, object.accountId == receipt.scope.accountId,
              object.attachmentId == receipt.attachmentId, object.contentSHA256 == receipt.contentSHA256,
              UInt64(object.byteCount) == receipt.byteCount, object.mediaType == receipt.metadata?.mediaType else { return false }
        return try await retainReconciledBytes(receipt, progress: progress)
    }

    private func retainReconciledBytes(_ receipt: AttachmentLocalDurabilityReceipt,
                                      progress: AttachmentUploadProgress?) async throws -> Bool {
        _ = try await resolveLocalAttachmentBytes(for: receipt)
        try await database.writeTransaction { transaction in
            guard let row = try transaction.getOptional(
                sql: "SELECT * FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id=?",
                parameters: [receipt.attachmentId.rawValue], mapper: QueueRow.init(cursor:)),
                  let record = row.validatedRecord, record.receipt == receipt,
                  try row.uploadProgress == progress else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            let json = String(decoding: try OperationContractCodec.encode(record.persistedEvidence), as: UTF8.self)
            let existing = try transaction.getOptional(
                sql: "SELECT evidence_json FROM \(AttachmentCapturePowerSyncTable.downloadedLogos) WHERE id=?",
                parameters: [receipt.attachmentId.rawValue]) { try $0.getString(name: "evidence_json") }
            if let existing, existing != json { throw AttachmentCapturePowerSyncStoreFailure.replayMismatch }
            if existing == nil {
                try transaction.execute(sql: "INSERT INTO \(AttachmentCapturePowerSyncTable.downloadedLogos)(id,evidence_json) VALUES(?,?)",
                    parameters: [receipt.attachmentId.rawValue, json])
            }
            try transaction.execute(sql: "DELETE FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id=?",
                parameters: [receipt.attachmentId.rawValue])
        }
        return true
    }

    func saveUploadProgress(_ progress: AttachmentUploadProgress,
                            for receipt: AttachmentLocalDurabilityReceipt) async throws {
        guard scope.contains(receipt.scope) else { throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch }
        if progress.expense != nil && (receipt.scope.parent.kind != .expense || progress.publication != nil) {
            throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
        }
        if let checkpoint = progress.checkpoint, checkpoint.offset > receipt.byteCount {
            throw SupabaseTransactionAttachmentUploadFailure.invalidCheckpoint
        }
        if case let .applied(revision, position) = progress.publication,
           revision <= 0 || !(0..<50).contains(position) {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        if case let .rejected(code) = progress.publication, code.isEmpty {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        try await ensureScopeBinding()
        let json = String(decoding: try JSONEncoder().encode(progress), as: UTF8.self)
        try await database.writeTransaction { transaction in
            guard let row = try transaction.getOptional(
                sql: "SELECT * FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id=?",
                parameters: [receipt.attachmentId.rawValue], mapper: QueueRow.init(cursor:)),
                  row.validatedRecord?.receipt == receipt else {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            if let existing = try row.uploadProgress?.publication, existing != .incomplete,
               existing != progress.publication {
                throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
            }
            if let existing = try row.uploadProgress?.expense {
                guard existing.projectId == progress.expense?.projectId,
                      existing.publication != .verified || progress.expense?.publication == .verified else {
                    throw AttachmentCapturePowerSyncStoreFailure.replayMismatch
                }
            }
            try transaction.execute(
                sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET upload_progress_json=? WHERE id=?",
                parameters: [json, receipt.attachmentId.rawValue])
            let saved = try transaction.getOptional(
                sql: "SELECT upload_progress_json FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id=?",
                parameters: [receipt.attachmentId.rawValue]) { try $0.getString(name: "upload_progress_json") }
            guard saved == json else { throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed }
        }
    }

    func resolveLocalAttachmentBytes(
        for receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> Data {
        // Namespace refusal precedes every database read so a foreign receipt
        // cannot be used as a local existence oracle.
        guard scope.contains(receipt.scope) else {
            throw AttachmentLocalByteResolutionFailure.scopeMismatch
        }
        try Task.checkCancellation()

        do {
            try await resolutionDatabaseAccessCheckpoint()
            try await ensureScopeBinding()
        } catch let failure as AttachmentCapturePowerSyncStoreFailure {
            if failure == .scopeMismatch {
                throw AttachmentLocalByteResolutionFailure.scopeMismatch
            }
            throw AttachmentLocalByteResolutionFailure.localReadUnavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AttachmentLocalByteResolutionFailure.localReadUnavailable
        }

        let row: QueueRow
        do {
            try await resolutionLookupCheckpoint()
            guard let existing = try await existingRow(
                attachmentIdentifier: receipt.attachmentId.rawValue
            ) else {
                throw AttachmentLocalByteResolutionFailure.receiptNotFound
            }
            row = existing
        } catch let failure as AttachmentLocalByteResolutionFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AttachmentLocalByteResolutionFailure.localReadUnavailable
        }

        guard row.environment == scope.environment.rawValue,
              row.principalID == scope.principalId.rawValue,
              row.accountID == scope.accountId.rawValue,
              let record = row.validatedRecord else {
            throw AttachmentLocalByteResolutionFailure.malformedLocalEvidence
        }
        guard record.receipt == receipt else {
            throw AttachmentLocalByteResolutionFailure.receiptMismatch
        }

        let evidence: AttachmentPersistedLocalObjectEvidence
        do {
            evidence = try record.persistedEvidence
        } catch {
            throw AttachmentLocalByteResolutionFailure.malformedLocalEvidence
        }

        do {
            let bytes = try await resolutionRead(evidence)
            try Task.checkCancellation()
            return bytes
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as AttachmentLocalByteVaultFailure {
            switch failure {
            case .scopeMismatch:
                throw AttachmentLocalByteResolutionFailure.scopeMismatch
            case .missingObject:
                throw AttachmentLocalByteResolutionFailure.missingBytes
            case .invalidLocalObjectIdentity, .linkSubstitution, .corruptObject:
                throw AttachmentLocalByteResolutionFailure.corruptBytes
            default:
                throw AttachmentLocalByteResolutionFailure.localReadUnavailable
            }
        } catch {
            throw AttachmentLocalByteResolutionFailure.localReadUnavailable
        }
    }

    public func orphanInventory() async throws -> [AttachmentVaultOrphan] {
        try await ensureScopeBinding()
        var referenced = Set(try await scopedRows().compactMap { row in
            row.validatedRecord?.receipt.localObjectId
        })
        referenced.formUnion(try await downloadedLogoObjectIDs())
        return try await vault.orphanInventory(referencedObjectIDs: referenced)
    }

    /// Download caching never creates a locally pending upload or a capture receipt.
    /// Callers must still authorize the current parent reference before displaying bytes.
    func cachedAccountLogo(_ reference: AccountBusinessLogoReference) async throws -> Data? {
        try await cachedDownloadedImage(reference.downloadedImageReference)
    }

    func cachedDownloadedImage(_ reference: DownloadedMediaObjectReference) async throws -> Data? {
        try await ensureScopeBinding()
        guard reference.accountId.rawValue.utf8.elementsEqual(scope.accountId.rawValue.utf8) else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        try await resolutionDatabaseAccessCheckpoint()
        guard let json = try await database.getOptional(
            sql: "SELECT evidence_json FROM \(AttachmentCapturePowerSyncTable.downloadedLogos) WHERE id = ?",
            parameters: [reference.attachmentId.rawValue],
            mapper: { try $0.getString(name: "evidence_json") }) else { return nil }
        let evidence = try decodedLogoEvidence(json)
        guard evidence.attachmentId == reference.attachmentId,
              evidence.contentSHA256 == reference.contentSHA256,
              evidence.byteCount == UInt64(reference.byteCount) else {
            throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
        }
        return try await vault.verifiedBytes(for: evidence)
    }

    func cacheAccountLogo(_ bytes: Data, reference: AccountBusinessLogoReference) async throws {
        try await cacheDownloadedImage(bytes, reference: reference.downloadedImageReference)
    }

    func cacheDownloadedImage(_ bytes: Data, reference: DownloadedMediaObjectReference) async throws {
        let id = reference.attachmentId.rawValue
        guard inFlight[id] == nil, !cachingAttachmentIDs.contains(id) else {
            throw AttachmentCapturePowerSyncStoreFailure.attachmentBusy
        }
        // Held across every await, including vault promotion and manifest commit.
        // enqueue checks this after its own scope-binding await and before admission.
        cachingAttachmentIDs.insert(id)
        defer { cachingAttachmentIDs.remove(id) }
        try await ensureScopeBinding()
        guard reference.accountId.rawValue.utf8.elementsEqual(scope.accountId.rawValue.utf8),
              bytes.count == reference.byteCount,
              try AttachmentContentSHA256.make(bytes: bytes) == reference.contentSHA256 else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        let timestamp = try timestamp(now())
        var repair = false
        do {
            if try await cachedDownloadedImage(reference) == bytes { return }
        } catch AttachmentLocalByteVaultFailure.missingObject {
            // The validated cache manifest survives; normal exclusive promotion
            // can restore the missing file without replacing any existing bytes.
        } catch AttachmentLocalByteVaultFailure.corruptObject {
            // cachedDownloadedImage already validated the exact cache manifest.
            // Never overwrite bytes owned by an accepted local upload receipt.
            guard try await existingRow(attachmentIdentifier: reference.attachmentId.rawValue) == nil else {
                throw AttachmentCapturePowerSyncStoreFailure.corruptBytes
            }
            repair = true
        }
        let capture = try LocalAttachmentCapture(attachmentId: reference.attachmentId,
            scope: AttachmentCaptureScope(environment: scope.environment, principalId: scope.principalId,
                accountId: scope.accountId,
                parent: LedgerEntityReference(kind: .account, id: EntityID(validating: scope.accountId.rawValue))),
            capturedAt: timestamp, bytes: bytes)
        let evidence = try await vault.persist(capture, persistedAt: timestamp, repairingDownloadedCache: repair)
        let json = String(decoding: try OperationContractCodec.encode(evidence), as: UTF8.self)
        let didRepair = repair
        try await database.writeTransaction { transaction in
            let exists = try transaction.getOptional(
                sql: "SELECT id FROM \(AttachmentCapturePowerSyncTable.downloadedLogos) WHERE id = ?",
                parameters: [reference.attachmentId.rawValue], mapper: { try $0.getString(name: "id") })
            if exists == nil {
                _ = try transaction.execute(sql: """
                    INSERT INTO \(AttachmentCapturePowerSyncTable.downloadedLogos)(id,evidence_json)
                    VALUES(?,?)
                    """, parameters: [reference.attachmentId.rawValue, json])
            } else if didRepair {
                _ = try transaction.execute(sql: "UPDATE \(AttachmentCapturePowerSyncTable.downloadedLogos) SET evidence_json = ? WHERE id = ?",
                    parameters: [json, reference.attachmentId.rawValue])
            }
        }
        // Verify durable readback even when another identical download won the insert.
        guard try await cachedDownloadedImage(reference) == bytes else {
            throw AttachmentCapturePowerSyncStoreFailure.corruptBytes
        }
    }

    private func decodedLogoEvidence(_ json: String) throws -> AttachmentPersistedLocalObjectEvidence {
        let evidence = try OperationContractCodec.decode(AttachmentPersistedLocalObjectEvidence.self,
                                                        from: Data(json.utf8))
        guard evidence.scope.environment == scope.environment,
              evidence.scope.principalId.rawValue.utf8.elementsEqual(scope.principalId.rawValue.utf8),
              evidence.scope.accountId.rawValue.utf8.elementsEqual(scope.accountId.rawValue.utf8),
              (evidence.scope.parent.kind == .transaction || evidence.scope.parent.kind == .expense ||
               (evidence.scope.parent.kind == .account &&
                evidence.scope.parent.id.rawValue.utf8.elementsEqual(scope.accountId.rawValue.utf8))) else {
            throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
        }
        return evidence
    }

    private func downloadedLogoObjectIDs() async throws -> Set<AttachmentLocalObjectID> {
        let rows = try await database.getAll(
            sql: "SELECT id,evidence_json FROM \(AttachmentCapturePowerSyncTable.downloadedLogos)",
            parameters: nil, mapper: { (try $0.getString(name: "id"), try $0.getString(name: "evidence_json")) })
        return try Set(rows.map { id, json in
            let evidence = try decodedLogoEvidence(json)
            guard evidence.attachmentId.rawValue.utf8.elementsEqual(id.utf8) else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            return evidence.localObjectId
        })
    }

    public func pendingWorkObservation() async throws -> AttachmentPendingWorkObservation {
        try await ensureScopeBinding()
        let rows = try await scopedRows()
        var queue: [AttachmentPendingWorkQueueEvidence] = []
        var referencedObjectIDs: Set<AttachmentLocalObjectID> = []
        queue.reserveCapacity(rows.count)

        for row in rows {
            guard let environment = row.environment,
                  let principalID = row.principalID,
                  let accountID = row.accountID else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            guard environment == scope.environment.rawValue,
                  principalID == scope.principalId.rawValue,
                  accountID == scope.accountId.rawValue else {
                throw AttachmentCapturePowerSyncStoreFailure.scopeMismatch
            }
            guard let record = row.validatedRecord,
                  record.receipt.scope.environment == scope.environment,
                  record.receipt.scope.principalId == scope.principalId,
                  record.receipt.scope.accountId == scope.accountId else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }

            let state = try await pendingWorkState(for: record)
            if state != row.state {
                try await setState(state, rowID: row.id)
            }
            queue.append(
                AttachmentPendingWorkQueueEvidence(
                    receipt: record.receipt,
                    state: state
                )
            )
            referencedObjectIDs.insert(record.receipt.localObjectId)
        }

        let orphans: [AttachmentVaultOrphan]
        do {
            referencedObjectIDs.formUnion(try await downloadedLogoObjectIDs())
            orphans = try await vault.orphanInventory(
                referencedObjectIDs: referencedObjectIDs
            )
        } catch let failure as AttachmentLocalByteVaultFailure {
            throw translate(failure)
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.mediaFailure(.storageFailure)
        }

        return AttachmentPendingWorkObservation(queue: queue, orphans: orphans)
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
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

    private func pendingWorkState(
        for record: QueueRecord
    ) async throws -> AttachmentPendingState {
        do {
            _ = try await vault.verifiedBytes(for: record.persistedEvidence)
            return .pending
        } catch let failure as AttachmentLocalByteVaultFailure {
            switch failure {
            case .missingObject:
                return .missing
            case .invalidLocalObjectIdentity, .linkSubstitution, .corruptObject:
                return .corrupt
            default:
                throw translate(failure)
            }
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.mediaFailure(.storageFailure)
        }
    }

    private func setState(_ state: AttachmentPendingState, rowID: String) async throws {
        do {
            _ = try await database.execute(
                sql: "UPDATE \(AttachmentCapturePowerSyncTable.queue) SET state = ? WHERE id = ?",
                parameters: [state.rawValue, rowID]
            )
            let persistedState = try await database.getOptional(
                sql: "SELECT state FROM \(AttachmentCapturePowerSyncTable.queue) WHERE id = ?",
                parameters: [rowID]
            ) { cursor in
                try cursor.getStringOptional(name: "state")
            }
            guard persistedState == state.rawValue else {
                throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
            }
        } catch let failure as AttachmentCapturePowerSyncStoreFailure {
            throw failure
        } catch {
            throw AttachmentCapturePowerSyncStoreFailure.queuePersistenceFailed
        }
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
                        sql: """
                            SELECT (SELECT count(*) FROM \(AttachmentCapturePowerSyncTable.queue))
                              + (SELECT count(*) FROM \(AttachmentCapturePowerSyncTable.downloadedLogos)) AS count
                            """,
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
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
    let metadata: AttachmentCaptureMetadata?

    init(_ capture: LocalAttachmentCapture) {
        attachmentID = capture.attachmentId
        scope = capture.scope
        capturedAt = capture.capturedAt
        bytes = capture.bytes
        metadata = capture.metadata
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
    let uploadProgressJSON: String?

    var uploadProgress: AttachmentUploadProgress? {
        get throws {
            guard let uploadProgressJSON else { return nil }
            guard let value = try? JSONDecoder().decode(AttachmentUploadProgress.self,
                from: Data(uploadProgressJSON.utf8)) else {
                throw AttachmentCapturePowerSyncStoreFailure.malformedQueueEvidence
            }
            return value
        }
    }

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
        uploadProgressJSON = try cursor.getStringOptional(name: "upload_progress_json")
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
