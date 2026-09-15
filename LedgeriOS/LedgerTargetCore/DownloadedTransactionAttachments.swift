import Foundation

public enum TransactionAttachmentSection: String, Codable, CaseIterable, Sendable { case receipts, other }

public enum TransactionAttachmentCaptureFailure: Error, Equatable, Sendable {
    case invalidCapture, unavailable, sectionFull, alreadyCapturing, pendingMetadataUnavailable
}

public protocol TransactionAttachmentCapturing: Sendable {
    /// Session identity for preparing a capture, not permission or acceptance.
    func transactionAttachmentCaptureScope(scope: TransactionScope, transactionId: TransactionID)
        async throws -> AttachmentCaptureScope
    func captureTransactionAttachment(_ capture: LocalAttachmentCapture, scope: TransactionScope)
        async throws -> AttachmentLocalDurabilityReceipt
}

/// Preserved section limit includes locally accepted files, not just synced rows.
/// The caller obtains the catalog through the current member/financial visibility query.
public enum TransactionAttachmentCaptureAdmission {
    public static let maximumAttachments = 50

    /// Runtime serializes this allocation per section. The resulting intent is
    /// fingerprinted with the accepted receipt, not inferred from wall-clock time.
    public static func assigningPlacement(_ capture: LocalAttachmentCapture,
        catalog: DownloadedTransactionAttachments, pending: [AttachmentLocalDurabilityReceipt]
    ) throws -> LocalAttachmentCapture {
        try validate(capture, catalog: catalog, pending: pending)
        guard let metadata = capture.metadata else { throw TransactionAttachmentCaptureFailure.invalidCapture }
        let placement: AttachmentCapturePlacement?
        if let existing = pending.first(where: { $0.attachmentId == capture.attachmentId }) {
            guard existing.scope == capture.scope, existing.capturedAt == capture.capturedAt,
                  existing.contentSHA256 == capture.contentSHA256, existing.byteCount == capture.byteCount,
                  existing.metadata?.mediaType == metadata.mediaType,
                  existing.metadata?.fileName == metadata.fileName,
                  existing.metadata?.transactionSection == metadata.transactionSection,
                  metadata.placement == nil || metadata.placement == existing.metadata?.placement else {
                throw TransactionAttachmentCaptureFailure.invalidCapture
            }
            placement = existing.metadata?.placement
        } else {
            guard metadata.placement == nil else { throw TransactionAttachmentCaptureFailure.invalidCapture }
            let sectionPending = pending.filter { $0.scope == capture.scope && $0.metadata?.transactionSection == catalog.section }
            let occupiedIDs = Set(catalog.attachments.map { $0.object.attachmentId.rawValue })
                .union(sectionPending.map { $0.attachmentId.rawValue })
            let highest = max(catalog.attachments.map(\.position).max() ?? -1,
                sectionPending.compactMap { $0.metadata?.placement.map { Int($0.localPosition) } }.max() ?? -1)
            guard highest < Int.max else { throw TransactionAttachmentCaptureFailure.invalidCapture }
            let next = max(occupiedIDs.count, highest + 1)
            guard let position = UInt32(exactly: next) else { throw TransactionAttachmentCaptureFailure.invalidCapture }
            placement = .init(localPosition: position, makePrimaryIfEmpty: occupiedIDs.isEmpty)
        }
        return try LocalAttachmentCapture(attachmentId: capture.attachmentId, scope: capture.scope,
            capturedAt: capture.capturedAt, bytes: capture.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: metadata.mediaType, fileName: metadata.fileName,
                transactionSection: metadata.transactionSection, placement: placement))
    }

    public static func validate(_ capture: LocalAttachmentCapture,
        catalog: DownloadedTransactionAttachments, pending: [AttachmentLocalDurabilityReceipt]
    ) throws {
        guard capture.scope.accountId == catalog.scope.accountId,
              capture.scope.parent.kind == .transaction,
              capture.scope.parent.id.rawValue == catalog.transactionId.rawValue,
              capture.metadata?.transactionSection == catalog.section else {
            throw TransactionAttachmentCaptureFailure.invalidCapture
        }
        // The shipped Other Images add flow has no PDF upload callback. PDF
        // viewing/pinning of an existing reference remains a separate capability.
        guard catalog.section == .receipts || capture.metadata?.mediaType != "application/pdf" else {
            throw TransactionAttachmentCaptureFailure.invalidCapture
        }
        guard catalog.isComplete, catalog.revision != nil else { throw TransactionAttachmentCaptureFailure.unavailable }
        if let existing = catalog.attachments.first(where: { $0.object.attachmentId == capture.attachmentId }) {
            guard existing.object.contentSHA256 == capture.contentSHA256,
                  UInt64(existing.object.byteCount) == capture.byteCount,
                  existing.object.mediaType == capture.metadata?.mediaType else {
                throw TransactionAttachmentCaptureFailure.invalidCapture
            }
        }
        var occupied = Set(catalog.attachments.map { $0.object.attachmentId.rawValue })
        for receipt in pending where receipt.scope == capture.scope {
            guard let metadata = receipt.metadata else {
                throw TransactionAttachmentCaptureFailure.pendingMetadataUnavailable
            }
            if metadata.transactionSection == catalog.section { occupied.insert(receipt.attachmentId.rawValue) }
        }
        // The same stable ID is a retry, not another slot. Its full identity is
        // still checked by the durable store before returning a receipt.
        guard occupied.contains(capture.attachmentId.rawValue) || occupied.count < maximumAttachments else {
            throw TransactionAttachmentCaptureFailure.sectionFull
        }
    }
}

public protocol DownloadedTransactionAttachmentReading: Sendable {
    /// Nil withdraws previously displayed media; missing metadata is a catalog
    /// with unknown revision, not an empty section. The runtime owns cancellation.
    func watchDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) -> AsyncThrowingStream<DownloadedTransactionAttachments?, Error>
    func readDownloadedTransactionAttachments(scope: TransactionScope, transactionId: TransactionID,
        section: TransactionAttachmentSection) async throws -> DownloadedTransactionAttachments
    /// The section revision and exact reference are revalidated around every
    /// cache/network await. Nil means bytes are not cached and download is disabled/unavailable.
    func loadDownloadedTransactionAttachment(catalog: DownloadedTransactionAttachments,
        attachment: DownloadedTransactionAttachment, allowDownload: Bool) async throws -> Data?
}

/// A current relationship, not a URL or permission to read cached bytes.
public struct DownloadedTransactionAttachment: Equatable, Sendable, Identifiable {
    public let id: EntityID
    public let object: DownloadedMediaObjectReference
    public let position: Int
    public let isPrimary: Bool
    public let fileName: String?
    public let localReceipt: AttachmentLocalDurabilityReceipt?

    public init(id: EntityID, object: DownloadedMediaObjectReference, position: Int,
                isPrimary: Bool, fileName: String?, localReceipt: AttachmentLocalDurabilityReceipt? = nil) throws {
        guard position >= 0 else { throw DownloadedTransactionAttachments.Failure.invalidEvidence }
        if let receipt = localReceipt {
            guard receipt.attachmentId == object.attachmentId, receipt.scope.accountId == object.accountId,
                  receipt.contentSHA256 == object.contentSHA256, receipt.byteCount == UInt64(object.byteCount),
                  receipt.metadata?.mediaType == object.mediaType else {
                throw DownloadedTransactionAttachments.Failure.invalidEvidence
            }
        }
        self.id = id; self.object = object; self.position = position
        self.isPrimary = isPrimary; self.fileName = fileName
        self.localReceipt = localReceipt
    }
}

/// Missing section metadata is unknown, never an empty gallery. Each section
/// retains its own revision so changing Other Images cannot authorize a receipt.
public struct DownloadedTransactionAttachments: Equatable, Sendable {
    public enum Failure: Error, Equatable { case unavailable, invalidEvidence }
    public let scope: TransactionScope
    public let transactionId: TransactionID
    public let section: TransactionAttachmentSection
    public let revision: Int64?
    public let isComplete: Bool
    public let attachments: [DownloadedTransactionAttachment]
    public let localUploadRejections: [AttachmentID: String]

    public func retains(_ attachment: DownloadedTransactionAttachment,
        from previous: DownloadedTransactionAttachments) -> Bool {
        revision != nil && revision == previous.revision && scope == previous.scope
            && transactionId == previous.transactionId && section == previous.section
            && previous.attachments.contains(attachment) && attachments.contains(attachment)
    }

    /// Rebind presentation after publication, never reuse an old read/export
    /// authorization. Callers must load through this catalog and returned reference.
    public func publishedReplacement(for attachment: DownloadedTransactionAttachment,
        from previous: DownloadedTransactionAttachments) -> DownloadedTransactionAttachment? {
        guard isComplete, previous.isComplete, let revision, let priorRevision = previous.revision,
              revision > priorRevision,
              scope == previous.scope, transactionId == previous.transactionId,
              section == previous.section, previous.attachments.contains(attachment),
              attachment.localReceipt != nil else { return nil }
        return attachments.first {
            $0.id == attachment.id && $0.object == attachment.object && $0.localReceipt == nil
        }
    }

    /// Local receipt is the durable pending parent relationship. It is not a
    /// claim that Storage upload or authoritative publication has completed.
    public func includingPending(_ receipts: [AttachmentLocalDurabilityReceipt],
        rejections: [AttachmentID: String] = [:]) throws -> Self {
        guard revision != nil else { return self }
        var combined = attachments
        var complete = isComplete
        let parent = try LedgerEntityReference(kind: .transaction, id: EntityID(validating: transactionId.rawValue))
        let matching = receipts.filter { $0.scope.accountId == scope.accountId && $0.scope.parent == parent }
            .sorted {
                // Older unpositioned receipts keep their prior deterministic order
                // before subsequently allocated positions; do not rewrite their fingerprints.
                let left = $0.metadata?.placement?.localPosition
                let right = $1.metadata?.placement?.localPosition
                if left != right {
                    if let left, let right { return left < right }
                    return left == nil
                }
                return ($0.persistedAt, $0.attachmentId.rawValue) < ($1.persistedAt, $1.attachmentId.rawValue)
            }
        for receipt in matching {
            guard let metadata = receipt.metadata else { complete = false; continue }
            guard metadata.transactionSection == section else { continue }
            if let synced = attachments.first(where: { $0.object.attachmentId == receipt.attachmentId }) {
                guard synced.object.contentSHA256 == receipt.contentSHA256,
                      UInt64(synced.object.byteCount) == receipt.byteCount,
                      synced.object.mediaType == metadata.mediaType else { throw Failure.invalidEvidence }
                continue
            }
            let object = try DownloadedMediaObjectReference(accountId: scope.accountId,
                attachmentId: receipt.attachmentId.rawValue, sha256: receipt.contentSHA256.rawValue,
                byteCount: String(receipt.byteCount), mediaType: metadata.mediaType,
                storagePath: "accounts/\(scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)",
                kind: metadata.mediaType == "application/pdf" ? .pdf : .image)
            // A new capture owns a new object and its initial relationship.
            // Publication must preserve this ID, not derive identity from the vault receipt.
            combined.append(try .init(id: EntityID(validating: receipt.attachmentId.rawValue),
                object: object, position: (combined.map(\.position).max() ?? -1) + 1,
                isPrimary: combined.isEmpty && (metadata.placement?.makePrimaryIfEmpty ?? true),
                fileName: metadata.fileName, localReceipt: receipt))
        }
        return try .init(scope: scope, transactionId: transactionId, section: section,
            revision: revision, isComplete: complete, attachments: combined,
            localUploadRejections: rejections.filter { id, _ in
                combined.contains { $0.object.attachmentId == id && $0.localReceipt != nil }
            })
    }

    public init(scope: TransactionScope, transactionId: TransactionID, section: TransactionAttachmentSection,
                revision: Int64?, isComplete: Bool, attachments: [DownloadedTransactionAttachment],
                localUploadRejections: [AttachmentID: String] = [:]) throws {
        guard localUploadRejections.allSatisfy({ id, code in
            !code.isEmpty && attachments.contains { $0.object.attachmentId == id && $0.localReceipt != nil }
        }) else { throw Failure.invalidEvidence }
        guard revision.map({ $0 > 0 }) ?? (!isComplete && attachments.isEmpty),
              attachments.allSatisfy({ attachment in
                  attachment.object.accountId.rawValue.utf8.elementsEqual(scope.accountId.rawValue.utf8)
                    && (attachment.localReceipt.map { $0.scope.parent.kind == .transaction
                        && $0.scope.parent.id.rawValue == transactionId.rawValue
                        && $0.metadata?.transactionSection == section } ?? true)
              }),
              Set(attachments.map { Array($0.id.rawValue.utf8) }).count == attachments.count,
              Set(attachments.map { Array($0.object.attachmentId.rawValue.utf8) }).count == attachments.count,
              Set(attachments.map(\.position)).count == attachments.count,
              attachments.filter(\.isPrimary).count <= 1 else { throw Failure.invalidEvidence }
        let ordered = attachments.sorted { $0.position < $1.position }
        guard !isComplete || ordered.enumerated().allSatisfy({ $0.offset == $0.element.position }) else {
            throw Failure.invalidEvidence
        }
        self.scope = scope; self.transactionId = transactionId; self.section = section
        self.revision = revision; self.isComplete = isComplete; self.attachments = ordered
        self.localUploadRejections = localUploadRejections
    }
}
