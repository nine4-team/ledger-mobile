import Foundation
import LedgerTargetCore

public struct ExpenseAttachmentUploadReservation: Equatable, Sendable {
    public let receipt: AttachmentLocalDurabilityReceipt
    public let projectId: EntityID
    public let storagePath: String
    fileprivate init(receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID, storagePath: String) {
        self.receipt = receipt
        self.projectId = projectId
        self.storagePath = storagePath
    }
}

public enum ExpenseAttachmentPublication: Codable, Equatable, Sendable {
    case incomplete
    case verified
}

/// Expense-specific admission and publication; the existing transport owns HTTP,
/// authentication, byte validation and resumable transfer. Verified is not reference readback.
public struct SupabaseExpenseAttachmentUpload: Sendable {
    private let transport: SupabaseTransactionAttachmentUpload

    public init(transport: SupabaseTransactionAttachmentUpload) { self.transport = transport }

    public func reserve(_ receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID) async throws -> ExpenseAttachmentUploadReservation {
        guard receipt.scope.parent.kind == .expense, let metadata = receipt.metadata,
              metadata.transactionSection == nil, receipt.byteCount > 0,
              receipt.byteCount <= 64 * 1024 * 1024 else {
            throw SupabaseTransactionAttachmentUploadFailure.unsupportedReceipt
        }
        let body: [String: Any] = [
            "p_id": receipt.attachmentId.rawValue, "p_account_id": receipt.scope.accountId.rawValue,
            "p_project_id": projectId.rawValue, "p_expense_id": receipt.scope.parent.id.rawValue,
            "p_content_sha256": receipt.contentSHA256.rawValue, "p_byte_count": String(receipt.byteCount),
            "p_media_type": metadata.mediaType, "p_file_name": metadata.fileName ?? NSNull(),
        ]
        let value = try await request("rest/v1/rpc/spike_begin_expense_attachment_upload", body: body)
        let path = "accounts/\(receipt.scope.accountId.rawValue)/attachments/\(receipt.attachmentId.rawValue)/\(receipt.contentSHA256.rawValue)"
        guard value["phase"] as? String == "awaiting_upload", value["bucket"] as? String == "ledger-attachments",
              value["storagePath"] as? String == path else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidReservation
        }
        try validate(value, receipt: receipt, projectId: projectId)
        return ExpenseAttachmentUploadReservation(receipt: receipt, projectId: projectId, storagePath: path)
    }

    public func verifyAndPublish(_ reservation: ExpenseAttachmentUploadReservation) async throws -> ExpenseAttachmentPublication {
        let (data, response) = try await transport.send(method: "POST",
            url: transport.supabaseURL.appendingPathComponent("functions/v1/verify-expense-attachment"),
            headers: ["Content-Type": "application/json"],
            body: JSONSerialization.data(withJSONObject: ["attachmentId": reservation.receipt.attachmentId.rawValue]))
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        if response.statusCode == 409, value["error"] as? String == "attachment_upload_incomplete" { return .incomplete }
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(statusCode: response.statusCode)
        }
        try validate(value, receipt: reservation.receipt, projectId: reservation.projectId)
        guard value["phase"] as? String == "verified" else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        return .verified
    }

    public func upload(_ candidate: AttachmentVerifiedUploadCandidate, reservation: ExpenseAttachmentUploadReservation,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping SupabaseTransactionAttachmentUpload.CheckpointHandler = { _ in }) async throws -> TransactionAttachmentUploadCheckpoint {
        guard candidate.receipt == reservation.receipt, let metadata = reservation.receipt.metadata else {
            throw SupabaseTransactionAttachmentUploadFailure.candidateMismatch
        }
        return try await transport.uploadReservedBytes(candidate, bucket: "ledger-attachments", storagePath: reservation.storagePath,
            mediaType: metadata.mediaType, byteCount: reservation.receipt.byteCount, resumeFrom: checkpoint, onCheckpoint: onCheckpoint)
    }

    public func publish(_ candidate: AttachmentVerifiedUploadCandidate, projectId: EntityID,
        resumeFrom checkpoint: TransactionAttachmentUploadCheckpoint? = nil,
        onCheckpoint: @escaping SupabaseTransactionAttachmentUpload.CheckpointHandler = { _ in },
        authorize: @escaping @Sendable () async throws -> Void = {}) async throws -> ExpenseAttachmentPublication {
        try await authorize()
        let reservation = try await reserve(candidate.receipt, projectId: projectId)
        try await authorize()
        let existing = try await verifyAndPublish(reservation)
        try await authorize()
        guard existing == .incomplete else { return existing }
        let save: SupabaseTransactionAttachmentUpload.CheckpointHandler = { checkpoint in
            try await onCheckpoint(checkpoint)
            try await authorize()
        }
        do {
            _ = try await upload(candidate, reservation: reservation, resumeFrom: checkpoint, onCheckpoint: save)
        } catch SupabaseTransactionAttachmentUploadFailure.expiredCheckpoint {
            try await authorize()
            let recovered = try await verifyAndPublish(reservation)
            try await authorize()
            guard recovered == .incomplete else { return recovered }
            _ = try await upload(candidate, reservation: reservation, onCheckpoint: save)
        }
        try await authorize()
        let result = try await verifyAndPublish(reservation)
        try await authorize()
        return result
    }

    private func request(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let (data, response) = try await transport.send(method: "POST", url: transport.supabaseURL.appendingPathComponent(path),
            headers: ["Content-Type": "application/json", "Accept": "application/vnd.pgrst.object+json"],
            body: JSONSerialization.data(withJSONObject: body))
        guard response.statusCode == 200 else {
            throw SupabaseTransactionAttachmentUploadFailure.requestRejected(statusCode: response.statusCode)
        }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseTransactionAttachmentUploadFailure.invalidResponse
        }
        return value
    }

    private func validate(_ value: [String: Any], receipt: AttachmentLocalDurabilityReceipt, projectId: EntityID) throws {
        guard value["attachmentId"] as? String == receipt.attachmentId.rawValue,
              value["accountId"] as? String == receipt.scope.accountId.rawValue,
              value["principalId"] as? String == receipt.scope.principalId.rawValue,
              value["projectId"] as? String == projectId.rawValue,
              value["expenseId"] as? String == receipt.scope.parent.id.rawValue,
              value["contentSHA256"] as? String == receipt.contentSHA256.rawValue,
              value["byteCount"] as? String == String(receipt.byteCount),
              value["mediaType"] as? String == receipt.metadata?.mediaType else {
            throw SupabaseTransactionAttachmentUploadFailure.reservationMismatch
        }
    }
}
