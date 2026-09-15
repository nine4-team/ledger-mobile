import CryptoKit
import Foundation
import LedgerTargetCore

/// Backend translation only: money and quantities cross JSON as decimal text.
struct CreateExpenseUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    init(_ command: CreateExpenseCommand) throws {
        let e = command.envelope, d = e.payload
        let wire = Wire(operationId: e.operationId.rawValue, accountId: e.accountId.rawValue,
            actorPrincipalId: e.actorPrincipalId.rawValue, projectId: d.projectId.rawValue,
            expenseId: d.expenseId.rawValue, contractVersion: e.contractVersion.rawValue,
            createdAtMs: String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            vendor: d.vendor, date: d.date, amountMinorUnits: String(d.finalAmount.minorUnits),
            currency: d.finalAmount.currency.rawValue, categoryId: d.categoryId.rawValue, notes: d.notes,
            receiptLines: d.receiptLines.map(Line.init), receiptAttachmentIds: d.receiptAttachmentIds.map(\.rawValue))
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

public protocol CreateExpenseCommandApplying: Sendable {
    func apply(_ command: CreateExpenseCommand) async throws -> CreateExpenseServerResult
}

public struct CreateExpenseServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: CreateExpenseCommand) throws {
        let e = command.envelope, request = try CreateExpenseUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.expenseId.rawValue,
              command_type == "create_expense", contract_version == "expense-create-v1",
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "expense_created" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }

    static let rejections: Set<String> = ["expense_project_unavailable", "expense_category_unavailable",
        "expense_receipt_invalid", "expense_integrity_conflict"]
}
