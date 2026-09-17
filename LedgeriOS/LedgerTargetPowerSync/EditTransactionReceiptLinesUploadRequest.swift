import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum TransactionReceiptLinesEditOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .transactionReceiptLinesEdit, accountId: accountId, uuid: uuid)
    }
}

public protocol EditTransactionReceiptLinesApplying: Sendable {
    func apply(_ command: EditTransactionReceiptLinesCommand) async throws -> EditTransactionReceiptLinesServerResult
}

public struct EditTransactionReceiptLinesServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let receipt_lines_revision: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64
    static let rejections: Set<String> = ["transaction_receipt_edit_stale", "transaction_receipt_edit_integrity_conflict"]

    func validate(for command: EditTransactionReceiptLinesCommand) throws {
        let e = command.envelope
        let request = try EditTransactionReceiptLinesUploadRequest(command)
        let validRevision: Bool
        if let raw = receipt_lines_revision, let revision = Int64(raw) {
            validRevision = revision > 0 && String(revision) == raw
        } else { validRevision = false }
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.transactionId.rawValue,
              command_type == "edit_transaction_receipt_lines", contract_version == e.contractVersion.rawValue,
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "transaction_receipt_lines_updated" && error_code == nil && validRevision)
                || (phase == "rejected" && result_code == nil && receipt_lines_revision == nil &&
                    Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
}

/// Exact decimal strings at the SQL boundary; no floating-point money conversion.
struct EditTransactionReceiptLinesUploadRequest: Sendable {
    enum Failure: Error { case payloadTooLarge }
    let commandJSON: String
    let fingerprint: String

    static func command(from entry: CrudEntry) throws -> EditTransactionReceiptLinesCommand {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.transactionReceiptLinesEditCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "transaction_id",
                                    "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command = try OperationContractCodec.decode(EditTransactionReceiptLinesCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        let e = command.envelope
        guard entry.id == e.operationId.rawValue,
              data["account_id"] == e.accountId.rawValue,
              data["actor_principal_id"] == e.actorPrincipalId.rawValue,
              data["transaction_id"] == e.payload.transactionId.rawValue,
              data["contract_version"] == e.contractVersion.rawValue,
              data["fingerprint"] == (try Self(command).fingerprint),
              json == String(decoding: try OperationContractCodec.encode(e), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(e.operationId, family: .transactionReceiptLinesEdit, accountId: e.accountId) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        return command
    }

    private struct Line: Encodable {
        let line: NonItemReceiptLine
        enum Keys: String, CodingKey { case id, description, amountMinorUnits, effect, quantity }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(line.id.rawValue, forKey: .id)
            try c.encode(line.description.rawValue, forKey: .description)
            try c.encode(String(line.magnitude.minorUnits), forKey: .amountMinorUnits)
            try c.encode(line.effect.rawValue, forKey: .effect)
            try c.encode(line.quantity.map(String.init), forKey: .quantity)
        }
    }
    private struct Wire: Encodable {
        let command: EditTransactionReceiptLinesCommand
        enum Keys: String, CodingKey {
            case operationId, accountId, actorPrincipalId, contractVersion, createdAtMs
            case transactionId, scopeKind, projectId, clientId, currency, expectedLines, lines
        }
        func encode(to encoder: Encoder) throws {
            let e = command.envelope, p = e.payload
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(e.operationId.rawValue, forKey: .operationId)
            try c.encode(e.accountId.rawValue, forKey: .accountId)
            try c.encode(e.actorPrincipalId.rawValue, forKey: .actorPrincipalId)
            try c.encode(e.contractVersion.rawValue, forKey: .contractVersion)
            try c.encode(String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())), forKey: .createdAtMs)
            try c.encode(p.transactionId.rawValue, forKey: .transactionId)
            try c.encode(p.scope.ownerKind == .project ? "project" : "business_inventory", forKey: .scopeKind)
            try c.encode(p.scope.projectId?.rawValue, forKey: .projectId)
            try c.encode(p.scope.clientId?.rawValue, forKey: .clientId)
            try c.encode(p.currency.rawValue, forKey: .currency)
            try c.encode(p.expectedLines.map { Line(line: $0) }, forKey: .expectedLines)
            try c.encode(p.lines.map { Line(line: $0) }, forKey: .lines)
        }
    }
    init(_ command: EditTransactionReceiptLinesCommand) throws {
        for lines in [command.envelope.payload.expectedLines, command.envelope.payload.lines] {
            let bytes = try OperationContractCodec.encode(lines.map { Line(line: $0) })
            // jsonb::text adds a space after each of five colons, four object
            // commas, and each array comma. Both sides emit quantity, even null.
            let postgresSpacing = lines.isEmpty ? 0 : lines.count * 10 - 1
            guard bytes.count + postgresSpacing <= 262_144 else { throw Failure.payloadTooLarge }
        }
        let bytes = try OperationContractCodec.encode(Wire(command: command))
        guard bytes.count <= 4 * 1024 * 1024 else { throw Failure.payloadTooLarge }
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(["p_command": commandJSON]) }
    }
}
