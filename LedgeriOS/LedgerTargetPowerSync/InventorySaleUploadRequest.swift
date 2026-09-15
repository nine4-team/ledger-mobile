import CryptoKit
import Foundation
import LedgerTargetCore

/// Provider-only translation. Decimal text prevents JavaScript/PostgREST from
/// rounding Int64 money; sorted JSON binds retries to the same server digest.
struct InventorySaleUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    init(_ command: InventorySaleCommand) throws {
        let envelope = command.envelope
        let wire = Wire(operationId: envelope.operationId.rawValue,
            accountId: envelope.accountId.rawValue, actorPrincipalId: envelope.actorPrincipalId.rawValue,
            projectId: envelope.payload.projectId.rawValue,
            contractVersion: envelope.contractVersion.rawValue,
            createdAtMs: String(Int64((envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            currency: envelope.payload.currency.rawValue, items: envelope.payload.items)
        let bytes = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(Body(p_command: commandJSON)) }
    }

    private struct Body: Encodable { let p_command: String }
    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, projectId, contractVersion, createdAtMs, currency: String
        let items: [InventorySaleSelection]
    }
}

public protocol InventorySaleCommandApplying: Sendable {
    func apply(_ command: InventorySaleCommand) async throws -> InventorySaleServerResult
}

public struct InventorySaleServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: InventorySaleCommand) throws {
        let envelope = command.envelope
        let request = try InventorySaleUploadRequest(command)
        guard operation_id == envelope.operationId.rawValue,
              account_id == envelope.accountId.rawValue,
              actor_principal_id == envelope.actorPrincipalId.rawValue,
              subject_id == envelope.payload.projectId.rawValue,
              command_type == "sell_inventory_items", contract_version == "inventory-sale-v1",
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "inventory_items_sold" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }

    static let rejections: Set<String> = [
        "sale_duplicate_item", "sale_destination_unavailable", "sale_furnishings_unresolved",
        "sale_item_invalid", "sale_item_unavailable", "sale_placement_stale",
        "sale_acquisition_unavailable", "sale_acquisition_ambiguous", "sale_currency_mismatch",
        "sale_price_stale", "sale_price_review_stale", "sale_integrity_conflict"
    ]
}
