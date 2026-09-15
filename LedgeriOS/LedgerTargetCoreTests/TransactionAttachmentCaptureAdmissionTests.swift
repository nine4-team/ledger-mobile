import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Transaction attachment capture admission")
struct TransactionAttachmentCaptureAdmissionTests {
    @Test("Same-clock captures retain chosen order and primary intent, not lexical ID order")
    func explicitCaptureOrdering() throws {
        let first = try capture("z-first")
        let positionedFirst = try TransactionAttachmentCaptureAdmission.assigningPlacement(first, catalog: catalog(), pending: [])
        let firstReceipt = try receipt(positionedFirst)
        let second = try capture("a-second")
        let positionedSecond = try TransactionAttachmentCaptureAdmission.assigningPlacement(second,
            catalog: catalog(), pending: [firstReceipt])
        let secondReceipt = try receipt(positionedSecond)
        #expect(firstReceipt.persistedAt == secondReceipt.persistedAt)
        #expect(firstReceipt.metadata?.placement == .init(localPosition: 0, makePrimaryIfEmpty: true))
        #expect(secondReceipt.metadata?.placement == .init(localPosition: 1, makePrimaryIfEmpty: false))
        let encoded = try OperationContractCodec.encode([secondReceipt, firstReceipt])
        let restored = try OperationContractCodec.decode([AttachmentLocalDurabilityReceipt].self, from: encoded)
        let projection = try catalog().includingPending(restored)
        #expect(projection.attachments.map(\.object.attachmentId.rawValue) == ["z-first", "a-second"])
        #expect(projection.attachments.map(\.isPrimary) == [true, false])
        #expect(try TransactionAttachmentCaptureAdmission.assigningPlacement(first,
            catalog: catalog(), pending: restored) == positionedFirst)
        let tampered = try LocalAttachmentCapture(attachmentId: second.attachmentId,
            scope: second.scope, capturedAt: second.capturedAt, bytes: second.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: nil,
                transactionSection: .receipts, placement: .init(localPosition: 0, makePrimaryIfEmpty: true)))
        #expect(throws: TransactionAttachmentCaptureFailure.invalidCapture) {
            try TransactionAttachmentCaptureAdmission.assigningPlacement(tampered,
                catalog: catalog(), pending: restored)
        }
    }

    @Test("Pending relationships retain identity, section, filename and first-image primary state")
    func pendingProjection() throws {
        let capture = try capture("pending")
        let local = try receipt(capture)
        let original = try catalog()
        let pending = try original.includingPending([local])
        let reference = try #require(pending.attachments.first)
        #expect(reference.localReceipt == local)
        #expect(reference.object.attachmentId == capture.attachmentId)
        #expect(reference.id.rawValue == capture.attachmentId.rawValue)
        #expect(reference.isPrimary && reference.position == 0)
        #expect(pending.isComplete)
        #expect(try original.includingPending([local]) == pending)
        let rejections = [local.attachmentId: "attachment_section_full"]
        let rejected = try original.includingPending([local], rejections: rejections)
        #expect(rejected.localUploadRejections == rejections)
        #expect(rejected.attachments == pending.attachments)
        #expect(rejected.retains(reference, from: pending)) // Status changes cannot close the viewer or lose its bytes.
        #expect(try catalog(section: .other).includingPending([local], rejections: rejections).localUploadRejections.isEmpty)
        #expect(try catalog(section: .other).includingPending([local]).attachments.isEmpty)
        #expect(try catalog(complete: false).includingPending([local]).attachments.isEmpty)
        let synced = try DownloadedTransactionAttachment(id: EntityID(validating: "published-reference"),
            object: reference.object, position: 0, isPrimary: true, fileName: reference.fileName)
        let applied = try catalog(attachments: [synced]).includingPending([local])
        #expect(applied.attachments == [synced])
        #expect(applied.attachments.first?.localReceipt == nil)
        #expect(try catalog(attachments: [synced]).includingPending([local], rejections: rejections).localUploadRejections.isEmpty)
    }

    @Test("Publication rebinds only the same pending reference and never extends old export authority")
    func publicationPresentation() throws {
        let pending = try catalog().includingPending([receipt(capture("pending"))])
        let original = try #require(pending.attachments.first)
        let published = try DownloadedTransactionAttachment(id: original.id, object: original.object,
            position: 0, isPrimary: true, fileName: original.fileName)
        let current = try DownloadedTransactionAttachments(scope: pending.scope,
            transactionId: pending.transactionId, section: pending.section,
            revision: 2, isComplete: true, attachments: [published])
        #expect(current.publishedReplacement(for: original, from: pending) == published)
        #expect(!current.retains(original, from: pending))
        #expect(current.publishedReplacement(for: published, from: current) == nil)
        #expect(try catalog().publishedReplacement(for: original, from: pending) == nil)
        #expect(try catalog(attachments: [published]).publishedReplacement(for: original, from: pending) == nil)
        let otherSection = try DownloadedTransactionAttachments(scope: pending.scope,
            transactionId: pending.transactionId, section: .other,
            revision: 2, isComplete: true, attachments: [published])
        #expect(otherSection.publishedReplacement(for: original, from: pending) == nil)
        let otherTransaction = try DownloadedTransactionAttachments(scope: pending.scope,
            transactionId: TransactionID(validating: "different"), section: pending.section,
            revision: 2, isComplete: true, attachments: [published])
        #expect(otherTransaction.publishedReplacement(for: original, from: pending) == nil)
        let differentReference = try DownloadedTransactionAttachment(id: EntityID(validating: "different"),
            object: original.object, position: 0, isPrimary: true, fileName: original.fileName)
        let replaced = try DownloadedTransactionAttachments(scope: pending.scope,
            transactionId: pending.transactionId, section: pending.section,
            revision: 2, isComplete: true, attachments: [differentReference])
        #expect(replaced.publishedReplacement(for: original, from: pending) == nil)
        let differentObject = try DownloadedMediaObjectReference(accountId: original.object.accountId,
            attachmentId: original.object.attachmentId.rawValue, sha256: String(repeating: "f", count: 64),
            byteCount: String(original.object.byteCount), mediaType: original.object.mediaType,
            storagePath: "accounts/account/attachments/pending/" + String(repeating: "f", count: 64))
        let changedBytes = try DownloadedTransactionAttachment(id: original.id, object: differentObject,
            position: 0, isPrimary: true, fileName: original.fileName)
        let changed = try DownloadedTransactionAttachments(scope: pending.scope,
            transactionId: pending.transactionId, section: pending.section,
            revision: 2, isComplete: true, attachments: [changedBytes])
        #expect(changed.publishedReplacement(for: original, from: pending) == nil)
    }

    @Test("Capacity includes queued files, allows exact retry, and isolates each section")
    func capacityAndRetry() throws {
        let queued = try (0..<50).map { try receipt(capture("queued-\($0)")) }
        let empty = try catalog()
        #expect(throws: TransactionAttachmentCaptureFailure.sectionFull) {
            try TransactionAttachmentCaptureAdmission.validate(capture("new"), catalog: empty, pending: queued)
        }
        try TransactionAttachmentCaptureAdmission.validate(capture("queued-0"), catalog: empty, pending: queued)
        try TransactionAttachmentCaptureAdmission.validate(capture("other-new", section: .other),
            catalog: catalog(section: .other), pending: queued)
        try TransactionAttachmentCaptureAdmission.validate(capture("new"), catalog: empty, pending: Array(queued.dropLast()))
    }

    @Test("Synced and queued references to the same stable attachment use one slot")
    func appliedOverlap() throws {
        let accepted = try receipt(capture("same"))
        let object = try DownloadedMediaObjectReference(accountId: accepted.scope.accountId,
            attachmentId: accepted.attachmentId.rawValue, sha256: accepted.contentSHA256.rawValue,
            byteCount: String(accepted.byteCount), mediaType: "image/png",
            storagePath: "accounts/account/attachments/same/\(accepted.contentSHA256.rawValue)")
        let attachment = try DownloadedTransactionAttachment(id: EntityID(validating: "reference"),
            object: object, position: 0, isPrimary: true, fileName: nil)
        let pending = try [accepted] + (0..<48).map { try receipt(capture("queued-\($0)")) }
        try TransactionAttachmentCaptureAdmission.validate(capture("last-slot"),
            catalog: catalog(attachments: [attachment]), pending: pending)
        let same = try capture("same")
        let changed = try LocalAttachmentCapture(attachmentId: same.attachmentId, scope: same.scope,
            capturedAt: same.capturedAt, bytes: Data([9]), metadata: same.metadata)
        #expect(throws: TransactionAttachmentCaptureFailure.invalidCapture) {
            try TransactionAttachmentCaptureAdmission.validate(changed,
                catalog: catalog(attachments: [attachment]), pending: [])
        }
    }

    @Test("Unknown catalogs and legacy sectionless pending work cannot silently permit capture")
    func incompleteEvidence() throws {
        #expect(throws: TransactionAttachmentCaptureFailure.unavailable) {
            try TransactionAttachmentCaptureAdmission.validate(capture("new"), catalog: catalog(complete: false), pending: [])
        }
        let original = try capture("legacy")
        let legacy = try LocalAttachmentCapture(attachmentId: original.attachmentId, scope: original.scope,
            capturedAt: original.capturedAt, bytes: original.bytes)
        #expect(throws: TransactionAttachmentCaptureFailure.pendingMetadataUnavailable) {
            try TransactionAttachmentCaptureAdmission.validate(capture("new"), catalog: catalog(), pending: [receipt(legacy)])
        }
        #expect(throws: TransactionAttachmentCaptureFailure.invalidCapture) {
            try TransactionAttachmentCaptureAdmission.validate(capture("new", section: .other), catalog: catalog(), pending: [])
        }
        let other = try capture("pdf-other", section: .other)
        let pdf = try LocalAttachmentCapture(attachmentId: other.attachmentId, scope: other.scope,
            capturedAt: other.capturedAt, bytes: other.bytes,
            metadata: AttachmentCaptureMetadata(mediaType: "application/pdf", fileName: nil, transactionSection: .other))
        #expect(throws: TransactionAttachmentCaptureFailure.invalidCapture) {
            try TransactionAttachmentCaptureAdmission.validate(pdf, catalog: catalog(section: .other), pending: [])
        }
    }

    private func capture(_ id: String, section: TransactionAttachmentSection = .receipts) throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(attachmentId: AttachmentID(validating: id),
            scope: AttachmentCaptureScope(environment: .targetLocal, principalId: PrincipalID(validating: "member"),
                accountId: AccountID(validating: "account"), parent: .init(kind: .transaction, id: EntityID(validating: "transaction"))),
            capturedAt: AttachmentEpochMilliseconds(validating: 1), bytes: Data([1, 2, 3]),
            metadata: AttachmentCaptureMetadata(mediaType: "image/png", fileName: nil, transactionSection: section))
    }

    private func receipt(_ capture: LocalAttachmentCapture) throws -> AttachmentLocalDurabilityReceipt {
        try AttachmentLocalDurabilityReceipt(accepting: capture,
            persistedEvidence: AttachmentPersistedLocalObjectEvidence(attachmentId: capture.attachmentId,
                scope: capture.scope, localObjectId: AttachmentLocalObjectID(validating: "local-\(capture.attachmentId.rawValue)"),
                byteCount: capture.byteCount, contentSHA256: capture.contentSHA256,
                persistedAt: AttachmentEpochMilliseconds(validating: 2)))
    }

    private func catalog(section: TransactionAttachmentSection = .receipts, complete: Bool = true,
        attachments: [DownloadedTransactionAttachment] = []) throws -> DownloadedTransactionAttachments {
        try .init(scope: .businessInventory(accountId: AccountID(validating: "account")),
            transactionId: TransactionID(validating: "transaction"), section: section,
            revision: complete ? 1 : nil, isComplete: complete, attachments: attachments)
    }
}
