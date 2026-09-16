import CryptoKit
import Foundation
import LedgerTargetCore

/// Uses the existing command RPC convention; revisions travel as exact decimal text.
struct ReturnUninvoicedItemsUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String

    init(_ command: ReturnUninvoicedItemsCommand) throws {
        let envelope = command.envelope
        let items = envelope.payload.items.map {
            ["itemId": $0.itemId.rawValue, "placementId": $0.placementId.rawValue,
             "chargeId": $0.chargeId.rawValue, "expectedChargeRevision": String($0.expectedChargeRevision),
             "inventoryPlacementId": $0.inventoryPlacementId.rawValue,
             "returnOccurrenceId": $0.returnOccurrenceId.rawValue]
        }
        let wire = Wire(operationId: envelope.operationId.rawValue,
            accountId: envelope.accountId.rawValue, actorPrincipalId: envelope.actorPrincipalId.rawValue,
            projectId: envelope.payload.projectId.rawValue, contractVersion: envelope.contractVersion.rawValue,
            createdAtMs: String(Int64((envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())),
            items: items)
        let bytes = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var rpcBody: Data {
        get throws { try OperationContractCodec.encode(["p_command": commandJSON]) }
    }

    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, projectId, contractVersion, createdAtMs: String
        let items: [[String: String]]
    }
}

public protocol ReturnUninvoicedItemsCommandApplying: Sendable {
    func apply(_ command: ReturnUninvoicedItemsCommand) async throws -> ReturnUninvoicedItemsServerResult
}

public struct ReturnUninvoicedItemsServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for command: ReturnUninvoicedItemsCommand) throws {
        let envelope = command.envelope
        let request = try ReturnUninvoicedItemsUploadRequest(command)
        guard operation_id == envelope.operationId.rawValue,
              account_id == envelope.accountId.rawValue,
              actor_principal_id == envelope.actorPrincipalId.rawValue,
              subject_id == envelope.payload.projectId.rawValue,
              command_type == "return_uninvoiced_items", contract_version == "return-uninvoiced-items-v1",
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint,
              request_sha256 == nil,
              client_created_at_ms == Int64((envelope.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "uninvoiced_items_returned" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }

    static let rejections: Set<String> = [
        "return_project_unavailable", "return_item_invalid", "return_item_unavailable", "return_duplicate_item",
        "return_placement_stale", "return_charge_stale", "return_charge_unavailable", "return_charge_invoiced",
        "return_charge_collected", "return_origin_unproven", "return_integrity_conflict"
    ]
}
