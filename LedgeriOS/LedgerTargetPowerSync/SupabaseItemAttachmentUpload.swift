import Foundation
import LedgerTargetCore

/// Item admission/publication over the existing authenticated resumable transport.
/// The publication value carries media revision/position, not accounting data.
public struct SupabaseItemAttachmentUpload: Sendable {
    private let transport: SupabaseTransactionAttachmentUpload
    public init(transport: SupabaseTransactionAttachmentUpload) { self.transport = transport }

    public func publish(_ candidate: AttachmentVerifiedUploadCandidate,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping SupabaseTransactionAttachmentUpload.CheckpointHandler = { _ in },
        authorize: @escaping @Sendable () async throws -> Void = {}) async throws -> TransactionAttachmentPublication {
        let receipt = candidate.receipt
        guard receipt.scope.parent.kind == .item, let metadata = receipt.metadata,
              metadata.transactionSection == nil, metadata.mediaType.hasPrefix("image/"),
              let placement = metadata.placement, receipt.byteCount > 0,
              receipt.byteCount <= 64 * 1024 * 1024 else {
            throw SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt
        }
        try await authorize()
        let (data, response) = try await transport.send(method: "POST",
            url: transport.supabaseURL.appendingPathComponent("rest/v1/rpc/spike_begin_item_attachment_upload"),
            headers: ["Content-Type": "application/json", "Accept": "application/vnd.pgrst.object+json"],
            body: JSONSerialization.data(withJSONObject: [
                "p_id": receipt.attachmentId.rawValue, "p_account_id": receipt.scope.accountId.rawValue,
                "p_item_id": receipt.scope.parent.id.rawValue, "p_content_sha256": receipt.contentSHA256.rawValue,
                "p_byte_count": String(receipt.byteCount), "p_media_type": metadata.mediaType,
                "p_file_name": metadata.fileName ?? NSNull(), "p_local_position": placement.localPosition,
                "p_make_primary_if_empty": placement.makePrimaryIfEmpty,
            ]))
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(statusCode: response.statusCode)
        }
        let value = try decode(data)
        try validateIdentity(value, receipt: receipt)
        let path = "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)"
        guard value["phase"] as? String == "awaiting_upload", value["bucket"] as? String == "ledger-attachments",
              value["storagePath"] as? String == path,
              value["contentSHA256"] as? String == receipt.contentSHA256.rawValue,
              value["byteCount"] as? String == String(receipt.byteCount),
              value["mediaType"] as? String == metadata.mediaType else {
            throw SupabaseTransactionAttachmentUploadFailure.reservationMismatch
        }
        try await authorize()
        let existing = try await verify(receipt)
        try await authorize()
        guard existing == .incomplete else { return existing }
        let save: SupabaseTransactionAttachmentUpload.CheckpointHandler = { value in
            try await onCheckpoint(value)
            try await authorize()
        }
        do {
            _ = try await transport.uploadReservedBytes(candidate, bucket: "ledger-attachments", storagePath: path,
                mediaType: metadata.mediaType, byteCount: receipt.byteCount, resumeFrom: checkpoint, onCheckpoint: save)
        } catch SupabaseTransactionAttachmentUploadFailure.expiredCheckpoint {
            try await authorize()
            let recovered = try await verify(receipt)
            try await authorize()
            guard recovered == .incomplete else { return recovered }
            _ = try await transport.uploadReservedBytes(candidate, bucket: "ledger-attachments", storagePath: path,
                mediaType: metadata.mediaType, byteCount: receipt.byteCount, onCheckpoint: save)
        }
        try await authorize()
        let result = try await verify(receipt)
        try await authorize()
        return result
    }

    private func verify(_ receipt: AttachmentLocalDurabilityReceipt) async throws -> TransactionAttachmentPublication {
        let (data, response) = try await transport.send(method: "POST",
            url: transport.supabaseURL.appendingPathComponent("functions/v1/verify-item-attachment"),
            headers: ["Content-Type": "application/json"],
            body: JSONSerialization.data(withJSONObject: ["attachmentId": receipt.attachmentId.rawValue]))
        let value = try decode(data)
        if response.statusCode == 409, value["error"] as? String == "attachment_upload_incomplete" { return .incomplete }
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(statusCode: response.statusCode)
        }
        try validateIdentity(value, receipt: receipt)
        if value["phase"] as? String == "rejected", let code = value["errorCode"] as? String, !code.isEmpty {
            return .rejected(code: code)
        }
        guard value["phase"] as? String == "applied", let rawRevision = value["revision"] as? String,
              let revision = Int64(rawRevision), revision > 0, String(revision) == rawRevision,
              let position = value["position"] as? Int, (0..<50).contains(position) else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        return .applied(revision: revision, position: position)
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        return value
    }
    private func validateIdentity(_ value: [String: Any], receipt: AttachmentLocalDurabilityReceipt) throws {
        for (field, expected) in [("attachmentId", receipt.attachmentId.rawValue),
            ("accountId", receipt.scope.accountId.rawValue), ("principalId", receipt.scope.principalId.rawValue),
            ("itemId", receipt.scope.parent.id.rawValue)] {
            guard let actual = value[field] as? String, actual.utf8.elementsEqual(expected.utf8) else {
                throw SupabaseTransactionAttachmentUploadFailure.reservationMismatch
            }
        }
    }
}
