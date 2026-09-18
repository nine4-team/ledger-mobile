import CryptoKit
import Foundation
import LedgerTargetCore

struct InventorySourceReturnUploadRequest: Sendable {
    let commandJSON: String
    let fingerprint: String
    init(_ command: ReturnInventoryItemsToSourceCommand) throws {
        let e = command.envelope
        let wire = Wire(operationId: e.operationId.rawValue, accountId: e.accountId.rawValue,
            actorPrincipalId: e.actorPrincipalId.rawValue, projectId: e.payload.projectId.rawValue,
            contractVersion: e.contractVersion.rawValue,
            createdAtMs: String(Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded())), items: e.payload.items)
        let bytes = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: bytes, as: UTF8.self)
        fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    var rpcBody: Data { get throws { try OperationContractCodec.encode(["p_command": commandJSON]) } }
    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, projectId, contractVersion, createdAtMs: String
        let items: [ReturnInventoryItemsToSourcePayload.Item]
    }
}
public protocol InventorySourceReturnCommandApplying: Sendable {
    func apply(_ command: ReturnInventoryItemsToSourceCommand) async throws -> InventorySourceReturnServerResult
}
public struct InventorySourceReturnServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64
    func validate(for command: ReturnInventoryItemsToSourceCommand) throws {
        let e = command.envelope, request = try InventorySourceReturnUploadRequest(command)
        guard operation_id == e.operationId.rawValue, account_id == e.accountId.rawValue,
              actor_principal_id == e.actorPrincipalId.rawValue, subject_id == e.payload.projectId.rawValue,
              command_type == "return_inventory_to_source", contract_version == "return-inventory-to-source-v1",
              command_fingerprint == request.fingerprint, envelope_sha256 == request.fingerprint, request_sha256 == nil,
              client_created_at_ms == Int64((e.clientCreatedAt.timeIntervalSince1970 * 1000).rounded()),
              server_received_at_ms >= 0, completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "inventory_items_returned_to_source" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
    static let rejections: Set<String> = ["source_return_duplicate_item", "source_return_destination_unavailable",
        "source_return_item_invalid", "source_return_item_unavailable", "source_return_placement_stale",
        "source_return_entry_unavailable", "source_return_integrity_conflict"]
}
