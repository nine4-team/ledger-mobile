import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Attachment Capture and Local-Durability Receipt Contracts")
struct AttachmentCaptureReceiptTests {
    @Test("Matching byte evidence produces one scoped path-free receipt")
    func matchingEvidenceProducesReceipt() throws {
        let capture = try Self.capture()
        let evidence = try Self.evidence(for: capture)
        let receipt = try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: evidence
        )

        #expect(receipt.attachmentId == capture.attachmentId)
        #expect(receipt.scope == capture.scope)
        #expect(receipt.localObjectId == evidence.localObjectId)
        #expect(receipt.byteCount == UInt64(Self.captureBytes.count))
        #expect(receipt.contentSHA256 == capture.contentSHA256)
        #expect(receipt.capturedAt == capture.capturedAt)
        #expect(receipt.persistedAt == evidence.persistedAt)
        #expect(receipt.fingerprint.rawValue.count == 64)

        let alternateEvidence = try Self.evidence(
            for: capture,
            localObjectID: "local-object-alternate"
        )
        let alternateReceipt = try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: alternateEvidence
        )
        #expect(alternateReceipt.attachmentId == receipt.attachmentId)
        #expect(alternateReceipt.localObjectId != receipt.localObjectId)

        let encoded = try OperationContractCodec.encode(receipt)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        let payloadBase64 = Self.captureBytes.base64EncodedString().lowercased()
        #expect(!text.contains(payloadBase64))
        for forbidden in ["file://", "https://", "gs://", "bucket", "bearer", "token"] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test("Canonical receipt evidence survives structured restart without raw bytes")
    func canonicalRestart() throws {
        let capture = try Self.capture()
        let receipt = try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: Self.evidence(for: capture)
        )
        let bytes = try OperationContractCodec.encode(receipt)
        let restored = try OperationContractCodec.decode(
            AttachmentLocalDurabilityReceipt.self,
            from: bytes
        )

        #expect(restored == receipt)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(!bytes.contains(Self.captureBytes))
        #expect(restored.scope.environment == .targetStaging)
        #expect(restored.scope.principalId.rawValue == "principal-attachment-test")
        #expect(restored.scope.accountId.rawValue == "account-attachment-test")
        #expect(restored.scope.parent.kind == .item)
    }

    @Test("Mismatched, malformed, and tampered evidence fails atomically")
    func invalidEvidenceFailsClosed() throws {
        #expect(Self.captureFailure {
            try LocalAttachmentCapture(
                attachmentId: Self.attachmentID,
                scope: Self.scope,
                capturedAt: Self.capturedAt,
                bytes: Data()
            )
        } == .emptyCaptureBytes)
        #expect(Self.captureFailure {
            try AttachmentLocalObjectID(validating: "file:///private/capture.jpg")
        } == .invalidLocalObjectID)
        #expect(Self.captureFailure {
            try AttachmentContentSHA256(validating: String(repeating: "A", count: 64))
        } == .invalidContentSHA256)
        #expect(Self.captureFailure {
            try AttachmentEpochMilliseconds(validating: -1)
        } == .invalidTimestamp)

        let capture = try Self.capture()
        #expect(Self.captureFailure {
            try Self.evidence(for: capture, byteCount: 0)
        } == .invalidByteCount)

        let mismatchedScopes: [AttachmentCaptureScope] = [
            try Self.scope(environment: .targetLocal),
            try Self.scope(principalID: "principal-other"),
            try Self.scope(accountID: "account-other"),
            try Self.scope(parentID: "item-other")
        ]
        for scope in mismatchedScopes {
            let evidence = try Self.evidence(for: capture, scope: scope)
            #expect(Self.captureFailure {
                try AttachmentLocalDurabilityReceipt(
                    accepting: capture,
                    persistedEvidence: evidence
                )
            } == .scopeMismatch)
        }

        let otherAttachment = try AttachmentID(validating: "attachment-other")
        #expect(Self.captureFailure {
            try AttachmentLocalDurabilityReceipt(
                accepting: capture,
                persistedEvidence: Self.evidence(
                    for: capture,
                    attachmentID: otherAttachment
                )
            )
        } == .attachmentIdentityMismatch)
        #expect(Self.captureFailure {
            try AttachmentLocalDurabilityReceipt(
                accepting: capture,
                persistedEvidence: Self.evidence(
                    for: capture,
                    byteCount: capture.byteCount + 1
                )
            )
        } == .byteEvidenceMismatch)
        let otherDigest = try AttachmentContentSHA256.make(bytes: Data("changed".utf8))
        #expect(Self.captureFailure {
            try AttachmentLocalDurabilityReceipt(
                accepting: capture,
                persistedEvidence: Self.evidence(
                    for: capture,
                    digest: otherDigest
                )
            )
        } == .byteEvidenceMismatch)

        let receipt = try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: Self.evidence(for: capture)
        )
        let tamperedReceipt = try Self.mutatedJSON(
            OperationContractCodec.encode(receipt),
            key: "fingerprint",
            value: String(repeating: "0", count: 64)
        )
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentLocalDurabilityReceipt.self,
                from: tamperedReceipt
            )
        } == .receiptFingerprintMismatch)

        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentCaptureScope.self,
                from: Data(#"{"environment":"targetStaging"}"#.utf8)
            )
        } == .invalidEncodedScope)
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentLocalObjectID.self,
                from: Data(#""bad/path""#.utf8)
            )
        } == .invalidEncodedLocalObjectID)
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentContentSHA256.self,
                from: Data(#""BAD""#.utf8)
            )
        } == .invalidEncodedContentSHA256)
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentPersistedLocalObjectEvidence.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedPersistedEvidence)
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentReceiptFingerprint.self,
                from: Data(#""BAD""#.utf8)
            )
        } == .invalidEncodedReceiptFingerprint)
        #expect(Self.captureFailure {
            try OperationContractCodec.decode(
                AttachmentLocalDurabilityReceipt.self,
                from: Data("{}".utf8)
            )
        } == .invalidEncodedReceipt)

        let diagnostics: [(AttachmentCaptureReceiptFailure, String)] = [
            (.emptyCaptureBytes, "attachment_capture_bytes_empty"),
            (.invalidLocalObjectID, "attachment_local_object_id_invalid"),
            (.invalidContentSHA256, "attachment_content_sha256_invalid"),
            (.invalidByteCount, "attachment_byte_count_invalid"),
            (.invalidTimestamp, "attachment_timestamp_invalid"),
            (.scopeMismatch, "attachment_capture_scope_mismatch"),
            (.attachmentIdentityMismatch, "attachment_capture_identity_mismatch"),
            (.byteEvidenceMismatch, "attachment_capture_byte_evidence_mismatch"),
            (.receiptFingerprintMismatch, "attachment_capture_receipt_fingerprint_mismatch"),
            (.localPersistenceFailed, "attachment_local_persistence_failed"),
            (.invalidEncodedScope, "attachment_capture_scope_encoding_invalid"),
            (.invalidEncodedLocalObjectID, "attachment_local_object_id_encoding_invalid"),
            (.invalidEncodedContentSHA256, "attachment_content_sha256_encoding_invalid"),
            (.invalidEncodedPersistedEvidence, "attachment_persisted_evidence_encoding_invalid"),
            (.invalidEncodedReceiptFingerprint, "attachment_receipt_fingerprint_encoding_invalid"),
            (.invalidEncodedReceipt, "attachment_capture_receipt_encoding_invalid")
        ]
        for (failure, diagnosticCode) in diagnostics {
            #expect(failure.diagnosticCode == diagnosticCode)
        }
    }

    @Test("A failed capture store returns no success receipt")
    func deterministicStoreFailureHasNoReceipt() async throws {
        let capture = try Self.capture()
        let failingStore = FailingAttachmentCaptureStore()
        var falseSuccess: AttachmentLocalDurabilityReceipt?
        do {
            falseSuccess = try await failingStore.enqueue(capture)
        } catch let failure as AttachmentCaptureReceiptFailure {
            #expect(failure == .localPersistenceFailed)
        }
        #expect(falseSuccess == nil)

        let evidenceStore = EvidenceAttachmentCaptureStore(
            evidence: try Self.evidence(for: capture)
        )
        let receipt = try await evidenceStore.enqueue(capture)
        #expect(receipt.attachmentId == capture.attachmentId)

        let wrongScopeStore = EvidenceAttachmentCaptureStore(
            evidence: try Self.evidence(
                for: capture,
                scope: Self.scope(accountID: "account-other")
            )
        )
        do {
            _ = try await wrongScopeStore.enqueue(capture)
            Issue.record("Mismatched evidence unexpectedly returned a receipt")
        } catch let failure as AttachmentCaptureReceiptFailure {
            #expect(failure == .scopeMismatch)
        }
    }

    private static let captureBytes = Data([0xde, 0xad, 0xbe, 0xef, 0x01, 0x02])

    private static var attachmentID: AttachmentID {
        get throws { try AttachmentID(validating: "attachment-capture-001") }
    }

    private static var capturedAt: AttachmentEpochMilliseconds {
        get throws { try AttachmentEpochMilliseconds(validating: 1_788_000_000_000) }
    }

    private static var scope: AttachmentCaptureScope {
        get throws { try scope() }
    }

    private static func scope(
        environment: LedgerEnvironmentKind = .targetStaging,
        principalID: String = "principal-attachment-test",
        accountID: String = "account-attachment-test",
        parentID: String = "item-attachment-test"
    ) throws -> AttachmentCaptureScope {
        AttachmentCaptureScope(
            environment: environment,
            principalId: try PrincipalID(validating: principalID),
            accountId: try AccountID(validating: accountID),
            parent: LedgerEntityReference(
                kind: .item,
                id: try EntityID(validating: parentID)
            )
        )
    }

    private static func capture() throws -> LocalAttachmentCapture {
        try LocalAttachmentCapture(
            attachmentId: attachmentID,
            scope: scope,
            capturedAt: capturedAt,
            bytes: captureBytes
        )
    }

    private static func evidence(
        for capture: LocalAttachmentCapture,
        attachmentID: AttachmentID? = nil,
        scope: AttachmentCaptureScope? = nil,
        localObjectID: String = "local-object-001",
        byteCount: UInt64? = nil,
        digest: AttachmentContentSHA256? = nil
    ) throws -> AttachmentPersistedLocalObjectEvidence {
        try AttachmentPersistedLocalObjectEvidence(
            attachmentId: attachmentID ?? capture.attachmentId,
            scope: scope ?? capture.scope,
            localObjectId: AttachmentLocalObjectID(validating: localObjectID),
            byteCount: byteCount ?? capture.byteCount,
            contentSHA256: digest ?? capture.contentSHA256,
            persistedAt: AttachmentEpochMilliseconds(
                validating: capture.capturedAt.rawValue + 25
            )
        )
    }

    private static func mutatedJSON(
        _ data: Data,
        key: String,
        value: Any
    ) throws -> Data {
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func captureFailure<Value>(
        _ body: () throws -> Value
    ) -> AttachmentCaptureReceiptFailure? {
        do {
            _ = try body()
            return nil
        } catch let failure as AttachmentCaptureReceiptFailure {
            return failure
        } catch {
            return nil
        }
    }
}

private struct FailingAttachmentCaptureStore: AttachmentCaptureStoring {
    func enqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        _ = capture
        throw AttachmentCaptureReceiptFailure.localPersistenceFailed
    }
}

private struct EvidenceAttachmentCaptureStore: AttachmentCaptureStoring {
    let evidence: AttachmentPersistedLocalObjectEvidence

    func enqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt {
        try AttachmentLocalDurabilityReceipt(
            accepting: capture,
            persistedEvidence: evidence
        )
    }
}
