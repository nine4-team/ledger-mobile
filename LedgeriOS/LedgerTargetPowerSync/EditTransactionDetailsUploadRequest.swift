import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum TransactionDetailsEditOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .transactionDetailsEdit, accountId: accountId, uuid: uuid)
    }
}

public protocol EditTransactionDetailsApplying: Sendable {
    func apply(_ command: EditTransactionDetailsCommand) async throws -> EditTransactionDetailsServerResult
}

public struct EditTransactionDetailsServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64
    static let rejections: Set<String> = ["transaction_edit_stale", "transaction_edit_integrity_conflict"]

    func validate(for command: EditTransactionDetailsCommand) throws {
        let e = command.envelope
        let request = try EditTransactionDetailsUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.transactionId.rawValue,
              command_type == "edit_transaction_details", contract_version == e.contractVersion.rawValue,
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "transaction_details_updated" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
}

/// Sparse fields retain omission versus explicit null. Decimal strings keep the
/// revision identical in Swift, JavaScript and Postgres, including above 2^53.
struct EditTransactionDetailsUploadRequest: Sendable {
    enum Failure: Error { case payloadTooLarge }
    static let maximumBytes = 4 * 1024 * 1024
    let commandJSON: String
    let fingerprint: String
    static func command(from entry: CrudEntry) throws -> EditTransactionDetailsCommand {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.transactionDetailsEditCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "transaction_id",
                                    "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command = try OperationContractCodec.decode(EditTransactionDetailsCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        let e = command.envelope
        let request = try Self(command)
        guard entry.id == e.operationId.rawValue,
              data["account_id"] == e.accountId.rawValue,
              data["actor_principal_id"] == e.actorPrincipalId.rawValue,
              data["transaction_id"] == e.payload.transactionId.rawValue,
              data["contract_version"] == e.contractVersion.rawValue,
              data["fingerprint"] == request.fingerprint,
              json == String(decoding: try OperationContractCodec.encode(e), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(e.operationId, family: .transactionDetailsEdit, accountId: e.accountId) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        return command
    }
    private struct Wire: Encodable {
        let command: EditTransactionDetailsCommand
        enum Keys: String, CodingKey {
            case operationId, accountId, actorPrincipalId, contractVersion, createdAtMs
            case transactionId, scopeKind, projectId, clientId, expectedRevision, changes
        }
        enum Fields: String, CodingKey { case source, notes, paymentMethod, hasEmailReceipt }
        func encode(to encoder: Encoder) throws {
            let e = command.envelope, payload = e.payload
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(e.operationId.rawValue, forKey: .operationId)
            try c.encode(e.accountId.rawValue, forKey: .accountId)
            try c.encode(e.actorPrincipalId.rawValue, forKey: .actorPrincipalId)
            try c.encode(e.contractVersion.rawValue, forKey: .contractVersion)
            try c.encode(String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())), forKey: .createdAtMs)
            try c.encode(payload.transactionId.rawValue, forKey: .transactionId)
            try c.encode(payload.scope.ownerKind == .project ? "project" : "business_inventory", forKey: .scopeKind)
            try c.encode(payload.scope.projectId?.rawValue, forKey: .projectId)
            try c.encode(payload.scope.clientId?.rawValue, forKey: .clientId)
            try c.encode(String(payload.expectedRevision), forKey: .expectedRevision)
            var fields = c.nestedContainer(keyedBy: Fields.self, forKey: .changes)
            for (key, change) in [(Fields.source, payload.changes.source), (.notes, payload.changes.notes),
                                   (.paymentMethod, payload.changes.paymentMethod)] {
                switch change {
                case .set(let text): try fields.encode(text, forKey: key)
                case .clear: try fields.encodeNil(forKey: key)
                case nil: break
                }
            }
            try fields.encodeIfPresent(payload.changes.hasEmailReceipt, forKey: .hasEmailReceipt)
        }
    }
    init(_ command: EditTransactionDetailsCommand) throws {
        let bytes = try OperationContractCodec.encode(Wire(command: command))
        guard bytes.count <= Self.maximumBytes else { throw Failure.payloadTooLarge }
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(["p_command": commandJSON]) }
    }
}
