import Foundation
import LedgerTargetCore
import PowerSync

struct TransactionAttachmentLocalReader: Sendable {
    let database: any PowerSyncDatabaseProtocol
    let principalId: PrincipalID
    let scope: TransactionScope
    var pendingStore: (any AccountWorkspaceAttachmentStoring)? = nil
    var attachmentDatabase: (any PowerSyncDatabaseProtocol)? = nil

    func watch(transactionId: TransactionID, section: TransactionAttachmentSection,
        receive: @Sendable @escaping (DownloadedTransactionAttachments?) async -> Bool) async throws {
        let identity = TransactionReceiptStreamIdentity(scope: scope)
        try await withOwnedSyncStreamWatch(subscribe: {
            try await database.syncStream(name: identity.name, params: identity.parameters).subscribe()
        }, observe: {
            let changes = try database.watch(sql: """
                SELECT EXISTS(SELECT 1 FROM spike_account_memberships WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_transactions WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_budget_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_local_operations WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_operation_results WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_receipt_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_items WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_placements WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_item_project_categories WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_client_payment_connections WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM spike_spaces WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM item_image_sets WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoices WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM collected_invoice_lines WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_attachment_sets WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM transaction_attachment_references WHERE account_id=?)
                UNION ALL SELECT EXISTS(SELECT 1 FROM ps_stream_subscriptions WHERE stream_name='transaction_receipts')
                """, parameters: Array(repeating: scope.accountId.rawValue, count: 16)) { try $0.getInt(index: 0) }
            if let attachmentDatabase {
                let events = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
                try await withThrowingTaskGroup(of: Void.self) { group in
                    defer { group.cancelAll(); events.continuation.finish() }
                    group.addTask {
                        do {
                            for try await _ in changes { events.continuation.yield(()) }
                            events.continuation.finish()
                        } catch { events.continuation.finish(throwing: error) }
                    }
                    group.addTask {
                        do {
                            let pending = try await attachmentDatabase.watch(sql: """
                                SELECT id,receipt_fingerprint,state,upload_progress_json FROM \(AttachmentCapturePowerSyncTable.queue)
                                WHERE parent_kind='transaction' AND parent_id=? ORDER BY persisted_at_ms,id
                                """, parameters: [transactionId.rawValue]) { try $0.getString(name: "id") }
                            for try await _ in pending { events.continuation.yield(()) }
                            events.continuation.finish()
                        } catch { events.continuation.finish(throwing: error) }
                    }
                    for try await _ in events.stream {
                        try Task.checkCancellation()
                        let catalog = try? await read(transactionId: transactionId, section: section)
                        try Task.checkCancellation()
                        guard await receive(catalog) else { return }
                    }
                }
            } else {
                for try await _ in changes {
                    try Task.checkCancellation()
                    let catalog = try? await read(transactionId: transactionId, section: section)
                    try Task.checkCancellation()
                    guard await receive(catalog) else { return }
                }
            }
        })
    }

    func load(catalog: DownloadedTransactionAttachments, attachment: DownloadedTransactionAttachment,
              cache: any DownloadedImageCaching,
              download: (@Sendable (DownloadedMediaObjectReference) async throws -> Data)?,
              authorizeAccess: @Sendable () async throws -> Void) async throws -> Data? {
        guard catalog.scope == scope, catalog.revision != nil, catalog.attachments.contains(attachment) else {
            throw DownloadedTransactionAttachments.Failure.invalidEvidence
        }
        @Sendable func authorize() async throws {
            try Task.checkCancellation()
            try await authorizeAccess()
            let current = try await read(transactionId: catalog.transactionId, section: catalog.section)
            guard current.revision == catalog.revision, current.attachments.contains(attachment) else {
                throw DownloadedTransactionAttachments.Failure.unavailable
            }
            try await authorizeAccess()
        }
        if let receipt = attachment.localReceipt {
            try await authorize()
            guard let pendingStore else { throw DownloadedTransactionAttachments.Failure.unavailable }
            let bytes = try await pendingStore.resolveLocalAttachmentBytes(for: receipt)
            try await authorize()
            return bytes
        }
        return try await loadAuthorizedDownloadedMedia(attachment.object, cache: cache, download: download, authorize: authorize)
    }

    func read(transactionId: TransactionID, section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
        // Authorize before reading local pending metadata and after the
        // cross-database await. Possession of bytes never implies access.
        let initial = try await readSynced(transactionId: transactionId, section: section)
        guard let pendingStore else { return initial }
        let parent = try LedgerEntityReference(kind: .transaction, id: EntityID(validating: transactionId.rawValue))
        let pending = try await pendingStore.pendingCaptureReceipts(parent: parent)
        let rejections = try await pendingStore.pendingCaptureRejections(parent: parent)
        let current = try await readSynced(transactionId: transactionId, section: section)
        return try current.includingPending(pending, rejections: rejections)
    }

    private func readSynced(transactionId: TransactionID, section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments {
        try await database.readTransaction { transaction in
            // Reuse current category overlays, membership, exact parent scope and
            // completed-stream checks in the SAME read checkpoint as references.
            let parent = try TransactionDetailPowerSyncQuery(database: database, principalId: principalId, scope: scope)
                .readRows(transaction: transaction, transactionId: transactionId)
            guard parent.count == 1 else { throw DownloadedTransactionAttachments.Failure.unavailable }
            func catalog(_ revision: Int64? = nil, complete: Bool = false,
                         attachments: [DownloadedTransactionAttachment] = []) throws -> DownloadedTransactionAttachments {
                try .init(scope: scope, transactionId: transactionId, section: section,
                          revision: revision, isComplete: complete, attachments: attachments)
            }
            let parameters: [Sendable?] = [scope.accountId.rawValue, transactionId.rawValue, section.rawValue]
            let markers = try transaction.getAll(sql: """
                SELECT revision,expected_count,typeof(expected_count) AS count_type
                FROM transaction_attachment_sets WHERE account_id=? AND transaction_id=? AND section=?
                """, parameters: parameters) {
                    (try $0.getString(name: "revision"), try $0.getInt(name: "expected_count"), try $0.getString(name: "count_type"))
                }
            guard markers.count == 1, let marker = markers.first,
                  let revision = Int64(marker.0), revision > 0, String(revision) == marker.0,
                  marker.1 >= 0, marker.2 == "integer" else { return try catalog() }
            let rows = try transaction.getAll(sql: """
                SELECT reference.id,reference.position,reference.is_primary,reference.file_name,
                  typeof(reference.position) AS position_type,typeof(reference.is_primary) AS primary_type,
                  reference.attachment_id AS object_id,reference.content_sha256,reference.byte_count,reference.media_type,reference.storage_path
                FROM transaction_attachment_references reference
                WHERE reference.account_id=? AND reference.transaction_id=? AND reference.section=? AND reference.set_revision=?
                ORDER BY reference.position,reference.id
                """, parameters: parameters + [marker.0]) { cursor -> DownloadedTransactionAttachment? in
                    do {
                        guard try cursor.getString(name: "position_type") == "integer",
                              try cursor.getString(name: "primary_type") == "integer" else { return nil }
                        let primary = try cursor.getInt(name: "is_primary")
                        guard primary == 0 || primary == 1 else { return nil }
                        let mediaType = try cursor.getString(name: "media_type")
                        let object = try DownloadedMediaObjectReference(accountId: scope.accountId,
                            attachmentId: cursor.getString(name: "object_id"), sha256: cursor.getString(name: "content_sha256"),
                            byteCount: cursor.getString(name: "byte_count"), mediaType: mediaType,
                            storagePath: cursor.getString(name: "storage_path"), kind: mediaType == "application/pdf" ? .pdf : .image)
                        return try .init(id: EntityID(validating: cursor.getString(name: "id")), object: object,
                            position: cursor.getInt(name: "position"), isPrimary: primary == 1,
                            fileName: cursor.getStringOptional(name: "file_name"))
                    } catch { return nil }
                }
            let attachments = rows.compactMap { $0 }
            let complete = rows.count == attachments.count && attachments.count == marker.1
                && attachments.enumerated().allSatisfy { $0.offset == $0.element.position }
            do { return try catalog(revision, complete: complete, attachments: attachments) }
            catch { return try catalog(revision) }
        }
    }
}
