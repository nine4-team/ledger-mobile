import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum ItemDetailsEditOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .itemDetailsEdit, accountId: accountId, uuid: uuid)
    }
}

public protocol EditItemDetailsApplying: Sendable {
    func apply(_ command: EditItemDetailsCommand) async throws -> EditItemDetailsServerResult
}

public struct EditItemDetailsServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    static let rejections: Set<String> = [
        "item_edit_unavailable", "item_edit_stale", "item_edit_integrity_conflict"
    ]

    func validate(for command: EditItemDetailsCommand) throws {
        let e = command.envelope
        let request = try EditItemDetailsUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue,
              subject_id == e.payload.items.first?.itemId.rawValue,
              command_type == "edit_item_details", contract_version == e.contractVersion.rawValue,
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "item_details_updated" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
}

/// The wire preserves omitted fields versus explicit clears, including bulk status.
struct EditItemDetailsUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    static func command(from entry: CrudEntry) throws -> EditItemDetailsCommand {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.itemDetailsEditCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "item_id",
                                    "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command = try OperationContractCodec.decode(EditItemDetailsCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        let e = command.envelope
        let request = try Self(command)
        guard entry.id == e.operationId.rawValue,
              data["account_id"] == e.accountId.rawValue,
              data["actor_principal_id"] == e.actorPrincipalId.rawValue,
              data["item_id"] == e.payload.items.first?.itemId.rawValue,
              data["contract_version"] == e.contractVersion.rawValue,
              data["fingerprint"] == request.fingerprint,
              json == String(decoding: try OperationContractCodec.encode(e), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(e.operationId, family: .itemDetailsEdit, accountId: e.accountId) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        return command
    }

    private struct Wire: Encodable {
        let command: EditItemDetailsCommand
        enum Keys: String, CodingKey {
            case operationId, accountId, actorPrincipalId, contractVersion, createdAtMs, items, changes
        }
        enum Fields: String, CodingKey { case name, sku, notes, status, bookmark, marketValue }
        func encode(to encoder: Encoder) throws {
            let e = command.envelope
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(e.operationId.rawValue, forKey: .operationId)
            try c.encode(e.accountId.rawValue, forKey: .accountId)
            try c.encode(e.actorPrincipalId.rawValue, forKey: .actorPrincipalId)
            try c.encode(e.contractVersion.rawValue, forKey: .contractVersion)
            try c.encode(String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())), forKey: .createdAtMs)
            try c.encode(e.payload.items.map {
                ["itemId": $0.itemId.rawValue, "expectedRevision": String($0.expectedRevision)]
            }, forKey: .items)
            var fields = c.nestedContainer(keyedBy: Fields.self, forKey: .changes)
            let changes = e.payload.changes
            for (key, change) in [(Fields.name, changes.name), (.sku, changes.sku), (.notes, changes.notes)] {
                switch change {
                case .set(let text): try fields.encode(text, forKey: key)
                case .clear: try fields.encodeNil(forKey: key)
                case nil: break
                }
            }
            if let status = changes.status {
                if status == .clear { try fields.encodeNil(forKey: .status) }
                else { try fields.encode(status.rawValue, forKey: .status) }
            }
            try fields.encodeIfPresent(changes.bookmark, forKey: .bookmark)
            switch changes.marketValue {
            case .set(let value):
                try fields.encode(["minorUnits": String(value.minorUnits), "currency": value.currency.rawValue], forKey: .marketValue)
            case .clear: try fields.encodeNil(forKey: .marketValue)
            case nil: break
            }
        }
    }

    init(_ command: EditItemDetailsCommand) throws {
        let bytes = try OperationContractCodec.encode(Wire(command: command))
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(["p_command": commandJSON]) }
    }
}
