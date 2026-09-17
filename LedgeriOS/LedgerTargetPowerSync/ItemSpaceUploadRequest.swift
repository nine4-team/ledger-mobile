import CryptoKit
import Foundation
import LedgerTargetCore

/// Provider encoding of the existing assign/clear commands. Domain command
/// identity remains unchanged; this hash binds the exact server request bytes.
struct ItemSpaceUploadRequest: Sendable {
    enum Failure: Error { case unsupportedContract, invalidTimestamp, invalidRevision }
    let commandJSON: String
    let fingerprint: String
    let operationId, accountId, principalId, subjectId, commandType: String
    let createdAtMs: Int64

    init(_ command: AssignItemsToSpaceCommand) throws {
        guard command.draft.operationContractVersion.rawValue == "item-space-assignment-v1" else {
            throw Failure.unsupportedContract
        }
        let d = command.draft
        try self.init(operationId: command.envelope.operationId.rawValue,
            accountId: d.accountId.rawValue, principalId: d.actorPrincipalId.rawValue,
            scope: d.scope, destination: d.destinationSpaceId.rawValue,
            destinationRevision: d.expectedSpaceRevision.rawValue,
            capturedAt: d.capturedAt, items: d.items.map {
                try Selection(itemId: $0.itemId.rawValue, revision: $0.expectedRevision.rawValue, currentSpace: nil)
            })
    }

    init(_ command: ClearItemSpaceAssignmentsCommand) throws {
        guard command.draft.operationContractVersion.rawValue == "item-space-clearing-v1" else {
            throw Failure.unsupportedContract
        }
        let d = command.draft
        try self.init(operationId: command.envelope.operationId.rawValue,
            accountId: d.accountId.rawValue, principalId: d.actorPrincipalId.rawValue,
            scope: d.scope, destination: nil, destinationRevision: nil,
            capturedAt: d.capturedAt, items: d.items.map {
                try Selection(itemId: $0.itemId.rawValue, revision: $0.expectedRevision.rawValue,
                              currentSpace: $0.currentSpaceId.rawValue)
            })
    }

    private init(operationId: String, accountId: String, principalId: String, scope: ItemPlacementScope,
                 destination: String?, destinationRevision: UInt64?, capturedAt: Date, items: [Selection]) throws {
        let milliseconds = (capturedAt.timeIntervalSince1970 * 1000).rounded()
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 1_000_000_000_000_000 else {
            throw Failure.invalidTimestamp
        }
        if let revision = destinationRevision, revision == 0 || revision >= UInt64(Int64.max) {
            throw Failure.invalidRevision
        }
        let kind: String, project: String?
        switch scope {
        case .businessInventory: kind = "business_inventory"; project = nil
        case .project(let id): kind = "project"; project = id.rawValue
        }
        self.operationId = operationId; self.accountId = accountId; self.principalId = principalId
        createdAtMs = Int64(milliseconds)
        subjectId = destination ?? items[0].itemId // Domain commands prohibit empty selections.
        commandType = destination == nil ? "clear_item_space_assignments" : "assign_items_to_space"
        let wire = Wire(operationId: operationId, accountId: accountId, actorPrincipalId: principalId,
            createdAtMs: String(createdAtMs), scopeKind: kind, projectId: project,
            destinationSpaceId: destination, expectedSpaceRevision: destinationRevision.map(String.init), items: items)
        let data = try OperationContractCodec.encode(wire)
        commandJSON = String(decoding: data, as: UTF8.self)
        fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var rpcBody: Data { get throws { try OperationContractCodec.encode(["p_command": commandJSON]) } }

    private struct Selection: Encodable {
        let itemId, expectedRevision: String
        let currentSpaceId: String?
        init(itemId: String, revision: UInt64, currentSpace: String?) throws {
            guard revision > 0, revision < UInt64(Int64.max) else { throw Failure.invalidRevision }
            self.itemId = itemId; expectedRevision = String(revision); currentSpaceId = currentSpace
        }
        enum CodingKeys: String, CodingKey { case itemId, expectedRevision, currentSpaceId }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(itemId, forKey: .itemId)
            try c.encode(expectedRevision, forKey: .expectedRevision)
            try c.encode(currentSpaceId, forKey: .currentSpaceId)
        }
    }

    private struct Wire: Encodable {
        let operationId, accountId, actorPrincipalId, createdAtMs, scopeKind: String
        let projectId, destinationSpaceId, expectedSpaceRevision: String?
        let items: [Selection]
        enum CodingKeys: String, CodingKey {
            case operationId, accountId, actorPrincipalId, contractVersion, createdAtMs,
                 scopeKind, projectId, destinationSpaceId, expectedSpaceRevision, items
        }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(operationId, forKey: .operationId)
            try c.encode(accountId, forKey: .accountId)
            try c.encode(actorPrincipalId, forKey: .actorPrincipalId)
            try c.encode("item-space-v1", forKey: .contractVersion)
            try c.encode(createdAtMs, forKey: .createdAtMs)
            try c.encode(scopeKind, forKey: .scopeKind)
            try c.encode(projectId, forKey: .projectId)
            try c.encode(destinationSpaceId, forKey: .destinationSpaceId)
            try c.encode(expectedSpaceRevision, forKey: .expectedSpaceRevision)
            try c.encode(items, forKey: .items)
        }
    }
}

public struct ItemSpaceServerResult: Decodable, Sendable {
    enum Failure: Error { case receiptMismatch }
    let operation_id, account_id, actor_principal_id, command_type, contract_version: String
    let command_fingerprint, envelope_sha256, subject_id, phase: String
    let request_sha256, result_code, error_code: String?
    let client_created_at_ms, server_received_at_ms, completed_at_ms: Int64

    func validate(for request: ItemSpaceUploadRequest) throws {
        guard operation_id == request.operationId, account_id == request.accountId,
              actor_principal_id == request.principalId, command_type == request.commandType,
              contract_version == "item-space-v1", command_fingerprint == request.fingerprint,
              envelope_sha256 == request.fingerprint, subject_id == request.subjectId, request_sha256 == nil,
              client_created_at_ms == request.createdAtMs, server_received_at_ms >= 0,
              completed_at_ms >= server_received_at_ms,
              (phase == "applied" && result_code == "item_spaces_updated" && error_code == nil)
                || (phase == "rejected" && result_code == nil && Self.rejections.contains(error_code ?? "")) else {
            throw Failure.receiptMismatch
        }
    }
    static let rejections: Set<String> = ["space_scope_unavailable", "space_item_unavailable",
        "space_destination_unavailable", "space_destination_stale", "space_item_scope_changed",
        "space_item_stale", "space_assignment_integrity_conflict"]
}
