import CryptoKit
import Foundation
import LedgerTargetCore
import PowerSync

public enum ItemPriceEditOperationIdentity {
    public static func make(accountId: AccountID, uuid: UUID) throws -> OperationID {
        try AccountBoundOperationIdentity.make(family: .itemPriceEdit, accountId: accountId, uuid: uuid)
    }
}

public protocol EditUncollectedItemPriceApplying: Sendable {
    func apply(_ command: EditUncollectedItemPriceCommand) async throws -> EditUncollectedItemPriceServerResult
}

public struct EditUncollectedItemPriceServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: EditUncollectedItemPriceCommand) throws {
        let e = command.envelope
        let request = try EditUncollectedItemPriceUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.itemId.rawValue,
              command_type == "edit_uncollected_item_price", contract_version == e.contractVersion.rawValue,
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "item_price_updated" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }

    static let rejections: Set<String> = [
        "price_project_unavailable", "price_invoice_unavailable", "price_item_unavailable",
        "price_placement_stale", "price_invoice_changed", "price_charge_unavailable",
        "price_charge_stale", "price_charge_collected", "price_acquisition_ambiguous",
        "price_currency_mismatch", "price_review_stale", "price_revision_stale", "price_integrity_conflict"
    ]
}

/// Exact decimal text at the provider boundary; never JSON floating-point money.
struct EditUncollectedItemPriceUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    /// Validate the SDK queue boundary before allowing a command to reach the RPC.
    /// Local ownership and access must still be checked by the upload lifecycle.
    static func command(from entry: CrudEntry) throws -> EditUncollectedItemPriceCommand {
        guard entry.op == .put, entry.table == LedgerPowerSyncTable.itemPriceEditCommands,
              let data = entry.opData, let json = data["envelope_json"] ?? nil,
              Set(data.keys) == Set(["account_id", "actor_principal_id", "item_id",
                                    "contract_version", "fingerprint", "envelope_json"]) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        let command = try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self,
            from: Data("{\"envelope\":\(json)}".utf8))
        let envelope = command.envelope
        let request = try Self(command)
        guard entry.id == envelope.operationId.rawValue,
              data["account_id"] == envelope.accountId.rawValue,
              data["actor_principal_id"] == envelope.actorPrincipalId.rawValue,
              data["item_id"] == envelope.payload.itemId.rawValue,
              data["contract_version"] == envelope.contractVersion.rawValue,
              data["fingerprint"] == request.fingerprint,
              json == String(decoding: try OperationContractCodec.encode(envelope), as: UTF8.self),
              AccountBoundOperationIdentity.isValid(envelope.operationId,
                  family: .itemPriceEdit, accountId: envelope.accountId) else {
            throw LocalOperationIdentityGuardFailure.malformedEvidence
        }
        return command
    }

    init(_ command: EditUncollectedItemPriceCommand) throws {
        let e = command.envelope, p = e.payload
        let fields: [String: String] = [
            "operationId": e.operationId.rawValue, "accountId": e.accountId.rawValue,
            "actorPrincipalId": e.actorPrincipalId.rawValue, "contractVersion": e.contractVersion.rawValue,
            "createdAtMs": String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            "projectId": p.projectId.rawValue, "itemId": p.itemId.rawValue,
            "placementId": p.placementId.rawValue, "occurrenceId": p.occurrenceId.rawValue,
            "expectedPriceRevision": String(p.expectedPriceRevision),
            "expectedChargeRevision": String(p.expectedChargeRevision),
            "requestedPriceMinorUnits": String(p.requestedPrice.minorUnits),
            "reviewedPriceMinorUnits": String(p.reviewedPrice.minorUnits),
            "currency": p.reviewedPrice.currency.rawValue
        ]
        let bytes = try OperationContractCodec.encode(fields)
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(["p_command": commandJSON]) }
    }
}
