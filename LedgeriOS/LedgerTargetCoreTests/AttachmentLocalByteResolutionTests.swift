import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Attachment Exact Local Byte Resolution Contracts")
struct AttachmentLocalByteResolutionTests {
    @Test("The port accepts the complete receipt and returns exact bytes")
    func exactReceiptPort() async throws {
        let receipt = try Self.receipt()
        let expected = Data([0x10, 0x20, 0x30, 0x40])
        let resolver = RecordingResolver(expectedReceipt: receipt, bytes: expected)

        let bytes = try await resolver.resolveLocalAttachmentBytes(for: receipt)

        #expect(bytes == expected)
        #expect(await resolver.receipts == [receipt])
    }

    @Test("Every failure has one stable non-sensitive diagnostic code")
    func diagnosticCodes() {
        let cases: [(AttachmentLocalByteResolutionFailure, String)] = [
            (.scopeMismatch, "attachment_local_byte_scope_mismatch"),
            (.receiptNotFound, "attachment_local_byte_receipt_not_found"),
            (.receiptMismatch, "attachment_local_byte_receipt_mismatch"),
            (.malformedLocalEvidence, "attachment_local_byte_evidence_malformed"),
            (.missingBytes, "attachment_local_byte_missing"),
            (.corruptBytes, "attachment_local_byte_corrupt"),
            (.localReadUnavailable, "attachment_local_byte_read_unavailable")
        ]

        for (failure, code) in cases {
            #expect(failure.diagnosticCode == code)
            #expect(!code.contains("/"))
            #expect(!code.contains("key"))
            #expect(!code.contains("receipt-001"))
        }
    }

    private static func receipt() throws -> AttachmentLocalDurabilityReceipt {
        let bytes = Data([0x10, 0x20, 0x30, 0x40])
        let scope = try AttachmentCaptureScope(
            environment: .targetLocal,
            principalId: PrincipalID(validating: "principal-attachment-resolver"),
            accountId: AccountID(validating: "account-attachment-resolver"),
            parent: LedgerEntityReference(
                kind: .item,
                id: EntityID(validating: "item-attachment-resolver")
            )
        )
        let capture = try LocalAttachmentCapture(
            attachmentId: AttachmentID(validating: "attachment-resolver-001"),
            scope: scope,
            capturedAt: AttachmentEpochMilliseconds(validating: 1_000),
            bytes: bytes
        )
        let evidence = try AttachmentPersistedLocalObjectEvidence(
            attachmentId: capture.attachmentId,
            scope: scope,
            localObjectId: AttachmentLocalObjectID(
                validating: String(repeating: "a", count: 64)
            ),
            byteCount: capture.byteCount,
            contentSHA256: capture.contentSHA256,
            persistedAt: AttachmentEpochMilliseconds(validating: 2_000)
        )
        return try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: evidence
        )
    }
}

private actor RecordingResolver: AttachmentLocalByteResolving {
    private let expectedReceipt: AttachmentLocalDurabilityReceipt
    private let bytes: Data
    private(set) var receipts: [AttachmentLocalDurabilityReceipt] = []

    init(expectedReceipt: AttachmentLocalDurabilityReceipt, bytes: Data) {
        self.expectedReceipt = expectedReceipt
        self.bytes = bytes
    }

    func resolveLocalAttachmentBytes(
        for receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> Data {
        receipts.append(receipt)
        guard receipt == expectedReceipt else {
            throw AttachmentLocalByteResolutionFailure.receiptMismatch
        }
        return bytes
    }
}
