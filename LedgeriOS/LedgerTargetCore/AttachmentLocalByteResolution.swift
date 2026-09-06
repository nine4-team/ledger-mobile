import Foundation

/// Stable failures for resolving one accepted local-durability receipt.
///
/// These cases deliberately expose no Attachment identity, parent identity,
/// filesystem path, provider detail, key material, SQL, or payload bytes.
public enum AttachmentLocalByteResolutionFailure: Error, Equatable, Sendable {
    case scopeMismatch
    case receiptNotFound
    case receiptMismatch
    case malformedLocalEvidence
    case missingBytes
    case corruptBytes
    case localReadUnavailable

    public var diagnosticCode: String {
        switch self {
        case .scopeMismatch:
            "attachment_local_byte_scope_mismatch"
        case .receiptNotFound:
            "attachment_local_byte_receipt_not_found"
        case .receiptMismatch:
            "attachment_local_byte_receipt_mismatch"
        case .malformedLocalEvidence:
            "attachment_local_byte_evidence_malformed"
        case .missingBytes:
            "attachment_local_byte_missing"
        case .corruptBytes:
            "attachment_local_byte_corrupt"
        case .localReadUnavailable:
            "attachment_local_byte_read_unavailable"
        }
    }
}

/// Backend-neutral access to bytes already accepted under one complete receipt.
///
/// The full receipt is the lookup authority. Implementations must not substitute
/// FIFO work, resolve by Attachment ID alone, consume pending work, or fall back
/// to a remote provider.
public protocol AttachmentLocalByteResolving: Sendable {
    func resolveLocalAttachmentBytes(
        for receipt: AttachmentLocalDurabilityReceipt
    ) async throws -> Data
}
