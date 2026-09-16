import CryptoKit
import Foundation
import LedgerTargetCore

/// Backend translation only: money and quantities cross JSON as decimal text.
struct CreateExpenseUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    init(_ command: CreateExpenseCommand) throws {
        let e = command.envelope, d = e.payload
        try self.init(operationId: e.operationId, accountId: e.accountId,
            actorPrincipalId: e.actorPrincipalId, contractVersion: e.contractVersion.rawValue,
            createdAt: e.clientCreatedAt, draft: d, expectedRevision: nil)
    }

    fileprivate init(operationId: OperationID, accountId: AccountID, actorPrincipalId: PrincipalID,
                     contractVersion: String, createdAt: Date, draft d: BusinessPaidExpenseDraft,
                     expectedRevision: Int64?) throws {
        let wire = Wire(operationId: operationId.rawValue, accountId: accountId.rawValue,
            actorPrincipalId: actorPrincipalId.rawValue, projectId: d.projectId.rawValue,
            expenseId: d.expenseId.rawValue, contractVersion: contractVersion,
            createdAtMs: String(Int64((createdAt.timeIntervalSince1970 * 1000).rounded())),
            vendor: d.vendor, date: d.date, amountMinorUnits: String(d.finalAmount.minorUnits),
            currency: d.finalAmount.currency.rawValue, categoryId: d.categoryId.rawValue, notes: d.notes,
            receiptLines: d.receiptLines.map(Line.init), receiptAttachmentIds: d.receiptAttachmentIds.map(\.rawValue),
            expectedRevision: expectedRevision.map(String.init))
        let data = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: data, as: UTF8.self)
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var rpcBody: Data { get throws { try OperationContractCodec.encode(Body(p_command: commandJSON)) } }
    private struct Body: Encodable { let p_command: String }
    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, projectId, expenseId, contractVersion, createdAtMs: String
        let vendor, date, amountMinorUnits, currency, categoryId, notes: String
        let receiptLines: [Line]
        let receiptAttachmentIds: [String]
        let expectedRevision: String?
    }
    private struct Line: Encodable {
        let id, description, magnitudeMinorUnits, currency, effect: String
        let quantity: String?
        init(_ line: NonItemReceiptLine) {
            id = line.id.rawValue; description = line.description.rawValue
            magnitudeMinorUnits = String(line.magnitude.minorUnits)
            currency = line.magnitude.currency.rawValue; effect = line.effect.rawValue
            quantity = line.quantity.map(String.init)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(description, forKey: .description)
            try c.encode(magnitudeMinorUnits, forKey: .magnitudeMinorUnits)
            try c.encode(currency, forKey: .currency); try c.encode(effect, forKey: .effect)
            // Explicit null distinguishes known absent quantity from malformed wire.
            try c.encode(quantity, forKey: .quantity)
        }
        private enum CodingKeys: String, CodingKey { case id, description, magnitudeMinorUnits, currency, effect, quantity }
    }
}

/// Shares the creation field encoding; only operation kind and revision differ.
struct EditExpenseUploadRequest: Sendable {
    private let encoded: CreateExpenseUploadRequest
    var commandJSON: String { encoded.commandJSON }
    var fingerprint: String { encoded.fingerprint }
    var rpcBody: Data { get throws { try encoded.rpcBody } }

    init(_ command: EditExpenseCommand) throws {
        let e = command.envelope
        encoded = try .init(operationId: e.operationId, accountId: e.accountId,
            actorPrincipalId: e.actorPrincipalId, contractVersion: e.contractVersion.rawValue,
            createdAt: e.clientCreatedAt, draft: e.payload.entry,
            expectedRevision: e.payload.expectedRevision)
    }
}

public protocol CreateExpenseCommandApplying: Sendable {
    func apply(_ command: CreateExpenseCommand) async throws -> CreateExpenseServerResult
}

public typealias CreateExpenseServerResult = ExpenseServerResult
public typealias EditExpenseServerResult = ExpenseServerResult

public protocol EditExpenseCommandApplying: Sendable {
    func apply(_ command: EditExpenseCommand) async throws -> EditExpenseServerResult
}

public struct ExpenseServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: CreateExpenseCommand) throws {
        let e = command.envelope, request = try CreateExpenseUploadRequest(command)
        try validate(operation: e.operationId, account: e.accountId, actor: e.actorPrincipalId,
            expense: e.payload.expenseId, createdAt: e.clientCreatedAt, fingerprint: request.fingerprint,
            kind: "create_expense", version: "expense-create-v1", success: "expense_created", rejections: Self.rejections)
    }

    func validate(for command: EditExpenseCommand) throws {
        let e = command.envelope, request = try EditExpenseUploadRequest(command)
        try validate(operation: e.operationId, account: e.accountId, actor: e.actorPrincipalId,
            expense: e.payload.entry.expenseId, createdAt: e.clientCreatedAt, fingerprint: request.fingerprint,
            kind: "edit_expense", version: "expense-edit-v1", success: "expense_edited",
            rejections: Self.editRejections)
    }

    private func validate(operation: OperationID, account: AccountID, actor: PrincipalID,
                          expense: ExpenseID, createdAt: Date, fingerprint: String,
                          kind: String, version: String, success: String, rejections: Set<String>) throws {
        guard operation_id == operation.rawValue, account_id == account.rawValue,
              actor_principal_id == actor.rawValue, subject_id == expense.rawValue,
              command_type == kind, contract_version == version,
              command_fingerprint == fingerprint, envelope_sha256 == fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((createdAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == success && error_code == nil)
                || (phase == "rejected" && result_code == nil && rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }

    static let rejections: Set<String> = ["expense_project_unavailable", "expense_category_unavailable",
        "expense_receipt_invalid", "expense_integrity_conflict"]
    static let editRejections = rejections.union(["expense_unavailable", "expense_collected",
        "expense_revision_conflict", "expense_receipt_change_unavailable"])
}
