import CryptoKit
import Foundation

public enum AttachmentCaptureReceiptFailure: Error, Equatable, Sendable {
    case emptyCaptureBytes
    case invalidLocalObjectID
    case invalidContentSHA256
    case invalidByteCount
    case invalidTimestamp
    case scopeMismatch
    case attachmentIdentityMismatch
    case byteEvidenceMismatch
    case receiptFingerprintMismatch
    case localPersistenceFailed
    case invalidEncodedScope
    case invalidEncodedLocalObjectID
    case invalidEncodedContentSHA256
    case invalidEncodedPersistedEvidence
    case invalidEncodedReceiptFingerprint
    case invalidEncodedReceipt

    public var diagnosticCode: String {
        switch self {
        case .emptyCaptureBytes:
            "attachment_capture_bytes_empty"
        case .invalidLocalObjectID:
            "attachment_local_object_id_invalid"
        case .invalidContentSHA256:
            "attachment_content_sha256_invalid"
        case .invalidByteCount:
            "attachment_byte_count_invalid"
        case .invalidTimestamp:
            "attachment_timestamp_invalid"
        case .scopeMismatch:
            "attachment_capture_scope_mismatch"
        case .attachmentIdentityMismatch:
            "attachment_capture_identity_mismatch"
        case .byteEvidenceMismatch:
            "attachment_capture_byte_evidence_mismatch"
        case .receiptFingerprintMismatch:
            "attachment_capture_receipt_fingerprint_mismatch"
        case .localPersistenceFailed:
            "attachment_local_persistence_failed"
        case .invalidEncodedScope:
            "attachment_capture_scope_encoding_invalid"
        case .invalidEncodedLocalObjectID:
            "attachment_local_object_id_encoding_invalid"
        case .invalidEncodedContentSHA256:
            "attachment_content_sha256_encoding_invalid"
        case .invalidEncodedPersistedEvidence:
            "attachment_persisted_evidence_encoding_invalid"
        case .invalidEncodedReceiptFingerprint:
            "attachment_receipt_fingerprint_encoding_invalid"
        case .invalidEncodedReceipt:
            "attachment_capture_receipt_encoding_invalid"
        }
    }
}

public struct AttachmentCaptureScope: Codable, Equatable, Sendable {
    public let environment: LedgerEnvironmentKind
    public let principalId: PrincipalID
    public let accountId: AccountID
    public let parent: LedgerEntityReference

    public init(
        environment: LedgerEnvironmentKind,
        principalId: PrincipalID,
        accountId: AccountID,
        parent: LedgerEntityReference
    ) {
        self.environment = environment
        self.principalId = principalId
        self.accountId = accountId
        self.parent = parent
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                environment: try container.decode(
                    LedgerEnvironmentKind.self,
                    forKey: .environment
                ),
                principalId: try container.decode(
                    PrincipalID.self,
                    forKey: .principalId
                ),
                accountId: try container.decode(AccountID.self, forKey: .accountId),
                parent: try container.decode(
                    LedgerEntityReference.self,
                    forKey: .parent
                )
            )
        } catch let failure as AttachmentCaptureReceiptFailure {
            throw failure
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedScope
        }
    }

    private enum CodingKeys: String, CodingKey {
        case environment
        case principalId
        case accountId
        case parent
    }
}

public struct AttachmentEpochMilliseconds: Codable, Equatable, Hashable,
    Comparable, Sendable {
    public let rawValue: Int64

    public init(validating rawValue: Int64) throws {
        guard rawValue >= 0 else {
            throw AttachmentCaptureReceiptFailure.invalidTimestamp
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(Int64.self))
        } catch let failure as AttachmentCaptureReceiptFailure {
            throw failure
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidTimestamp
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AttachmentLocalObjectID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= 128,
              rawValue.unicodeScalars.allSatisfy(allowed.contains) else {
            throw AttachmentCaptureReceiptFailure.invalidLocalObjectID
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedLocalObjectID
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AttachmentContentSHA256: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw AttachmentCaptureReceiptFailure.invalidContentSHA256
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedContentSHA256
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func make(bytes: Data) throws -> Self {
        try Self(validating: Self.hexDigest(bytes))
    }

    fileprivate static func hexDigest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AttachmentReceiptFingerprint: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    private init(validating rawValue: String) throws {
        let lowercaseHexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.utf8.count == 64,
              rawValue.unicodeScalars.allSatisfy(lowercaseHexadecimal.contains) else {
            throw AttachmentCaptureReceiptFailure.invalidEncodedReceiptFingerprint
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            try self.init(validating: container.decode(String.self))
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedReceiptFingerprint
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    fileprivate static func make<Material: Encodable>(
        material: Material
    ) throws -> Self {
        let bytes = try OperationContractCodec.encode(material)
        return try Self(validating: AttachmentContentSHA256.hexDigest(bytes))
    }
}

public struct LocalAttachmentCapture: Equatable, Sendable {
    public let attachmentId: AttachmentID
    public let scope: AttachmentCaptureScope
    public let capturedAt: AttachmentEpochMilliseconds
    public let bytes: Data
    public let byteCount: UInt64
    public let contentSHA256: AttachmentContentSHA256

    public init(
        attachmentId: AttachmentID,
        scope: AttachmentCaptureScope,
        capturedAt: AttachmentEpochMilliseconds,
        bytes: Data
    ) throws {
        guard !bytes.isEmpty else {
            throw AttachmentCaptureReceiptFailure.emptyCaptureBytes
        }
        self.attachmentId = attachmentId
        self.scope = scope
        self.capturedAt = capturedAt
        self.bytes = bytes
        self.byteCount = UInt64(bytes.count)
        self.contentSHA256 = try AttachmentContentSHA256.make(bytes: bytes)
    }
}

public struct AttachmentPersistedLocalObjectEvidence: Codable, Equatable, Sendable {
    public let attachmentId: AttachmentID
    public let scope: AttachmentCaptureScope
    public let localObjectId: AttachmentLocalObjectID
    public let byteCount: UInt64
    public let contentSHA256: AttachmentContentSHA256
    public let persistedAt: AttachmentEpochMilliseconds

    public init(
        attachmentId: AttachmentID,
        scope: AttachmentCaptureScope,
        localObjectId: AttachmentLocalObjectID,
        byteCount: UInt64,
        contentSHA256: AttachmentContentSHA256,
        persistedAt: AttachmentEpochMilliseconds
    ) throws {
        guard byteCount > 0 else {
            throw AttachmentCaptureReceiptFailure.invalidByteCount
        }
        self.attachmentId = attachmentId
        self.scope = scope
        self.localObjectId = localObjectId
        self.byteCount = byteCount
        self.contentSHA256 = contentSHA256
        self.persistedAt = persistedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                attachmentId: container.decode(
                    AttachmentID.self,
                    forKey: .attachmentId
                ),
                scope: container.decode(AttachmentCaptureScope.self, forKey: .scope),
                localObjectId: container.decode(
                    AttachmentLocalObjectID.self,
                    forKey: .localObjectId
                ),
                byteCount: container.decode(UInt64.self, forKey: .byteCount),
                contentSHA256: container.decode(
                    AttachmentContentSHA256.self,
                    forKey: .contentSHA256
                ),
                persistedAt: container.decode(
                    AttachmentEpochMilliseconds.self,
                    forKey: .persistedAt
                )
            )
        } catch let failure as AttachmentCaptureReceiptFailure {
            throw failure
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedPersistedEvidence
        }
    }

    private enum CodingKeys: String, CodingKey {
        case attachmentId
        case scope
        case localObjectId
        case byteCount
        case contentSHA256
        case persistedAt
    }
}

public struct AttachmentLocalDurabilityReceipt: Codable, Equatable, Sendable {
    public let attachmentId: AttachmentID
    public let scope: AttachmentCaptureScope
    public let localObjectId: AttachmentLocalObjectID
    public let byteCount: UInt64
    public let contentSHA256: AttachmentContentSHA256
    public let capturedAt: AttachmentEpochMilliseconds
    public let persistedAt: AttachmentEpochMilliseconds
    public let fingerprint: AttachmentReceiptFingerprint

    public init(
        accepting capture: LocalAttachmentCapture,
        persistedEvidence: AttachmentPersistedLocalObjectEvidence
    ) throws {
        guard capture.scope == persistedEvidence.scope else {
            throw AttachmentCaptureReceiptFailure.scopeMismatch
        }
        guard capture.attachmentId == persistedEvidence.attachmentId else {
            throw AttachmentCaptureReceiptFailure.attachmentIdentityMismatch
        }
        guard capture.byteCount == persistedEvidence.byteCount,
              capture.contentSHA256 == persistedEvidence.contentSHA256 else {
            throw AttachmentCaptureReceiptFailure.byteEvidenceMismatch
        }

        self.attachmentId = capture.attachmentId
        self.scope = capture.scope
        self.localObjectId = persistedEvidence.localObjectId
        self.byteCount = capture.byteCount
        self.contentSHA256 = capture.contentSHA256
        self.capturedAt = capture.capturedAt
        self.persistedAt = persistedEvidence.persistedAt
        self.fingerprint = try Self.makeFingerprint(
            attachmentId: attachmentId,
            scope: scope,
            localObjectId: localObjectId,
            byteCount: byteCount,
            contentSHA256: contentSHA256,
            capturedAt: capturedAt,
            persistedAt: persistedAt
        )
    }

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let attachmentId = try container.decode(
                AttachmentID.self,
                forKey: .attachmentId
            )
            let scope = try container.decode(
                AttachmentCaptureScope.self,
                forKey: .scope
            )
            let localObjectId = try container.decode(
                AttachmentLocalObjectID.self,
                forKey: .localObjectId
            )
            let byteCount = try container.decode(UInt64.self, forKey: .byteCount)
            guard byteCount > 0 else {
                throw AttachmentCaptureReceiptFailure.invalidByteCount
            }
            let contentSHA256 = try container.decode(
                AttachmentContentSHA256.self,
                forKey: .contentSHA256
            )
            let capturedAt = try container.decode(
                AttachmentEpochMilliseconds.self,
                forKey: .capturedAt
            )
            let persistedAt = try container.decode(
                AttachmentEpochMilliseconds.self,
                forKey: .persistedAt
            )
            let fingerprint = try container.decode(
                AttachmentReceiptFingerprint.self,
                forKey: .fingerprint
            )
            let expectedFingerprint = try Self.makeFingerprint(
                attachmentId: attachmentId,
                scope: scope,
                localObjectId: localObjectId,
                byteCount: byteCount,
                contentSHA256: contentSHA256,
                capturedAt: capturedAt,
                persistedAt: persistedAt
            )
            guard fingerprint == expectedFingerprint else {
                throw AttachmentCaptureReceiptFailure.receiptFingerprintMismatch
            }

            self.attachmentId = attachmentId
            self.scope = scope
            self.localObjectId = localObjectId
            self.byteCount = byteCount
            self.contentSHA256 = contentSHA256
            self.capturedAt = capturedAt
            self.persistedAt = persistedAt
            self.fingerprint = fingerprint
        } catch let failure as AttachmentCaptureReceiptFailure {
            throw failure
        } catch {
            throw AttachmentCaptureReceiptFailure.invalidEncodedReceipt
        }
    }

    private static func makeFingerprint(
        attachmentId: AttachmentID,
        scope: AttachmentCaptureScope,
        localObjectId: AttachmentLocalObjectID,
        byteCount: UInt64,
        contentSHA256: AttachmentContentSHA256,
        capturedAt: AttachmentEpochMilliseconds,
        persistedAt: AttachmentEpochMilliseconds
    ) throws -> AttachmentReceiptFingerprint {
        try AttachmentReceiptFingerprint.make(
            material: AttachmentReceiptFingerprintMaterial(
                contract: "attachment_capture_receipt_v1",
                attachmentId: attachmentId,
                scope: scope,
                localObjectId: localObjectId,
                byteCount: byteCount,
                contentSHA256: contentSHA256,
                capturedAt: capturedAt,
                persistedAt: persistedAt
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case attachmentId
        case scope
        case localObjectId
        case byteCount
        case contentSHA256
        case capturedAt
        case persistedAt
        case fingerprint
    }
}

public protocol AttachmentCaptureStoring: Sendable {
    func enqueue(
        _ capture: LocalAttachmentCapture
    ) async throws -> AttachmentLocalDurabilityReceipt
}

private struct AttachmentReceiptFingerprintMaterial: Codable, Sendable {
    let contract: String
    let attachmentId: AttachmentID
    let scope: AttachmentCaptureScope
    let localObjectId: AttachmentLocalObjectID
    let byteCount: UInt64
    let contentSHA256: AttachmentContentSHA256
    let capturedAt: AttachmentEpochMilliseconds
    let persistedAt: AttachmentEpochMilliseconds
}
