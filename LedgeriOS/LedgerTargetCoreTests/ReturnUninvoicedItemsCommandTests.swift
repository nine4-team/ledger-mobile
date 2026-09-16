import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Return uninvoiced Items intent")
struct ReturnUninvoicedItemsCommandTests {
    private func item(revision: Int64 = 1) throws -> ReturnUninvoicedItemsPayload.Item {
        try .init(itemId: .init(validating: "item"), placementId: .init(validating: "project-placement"),
            chargeId: .init(validating: "sale-charge"), expectedChargeRevision: revision,
            inventoryPlacementId: .init(validating: "inventory-placement"),
            returnOccurrenceId: .init(validating: "return-occurrence"))
    }

    private func command() throws -> ReturnUninvoicedItemsCommand {
        try .init(operationId: .init(validating: "return-operation"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1000.125),
            payload: .init(projectId: .init(validating: "project"), items: [item(revision: Int64.max - 1)]))
    }

    @Test func exactReplayRetainsSaleAndReturnIdentities() throws {
        let original = try command(), bytes = try OperationContractCodec.encode(original)
        let restored = try OperationContractCodec.decode(ReturnUninvoicedItemsCommand.self, from: bytes)
        #expect(restored.envelope.payload == original.envelope.payload)
        #expect(restored.envelope.operationId == original.envelope.operationId)
        #expect(try OperationContractCodec.encode(restored) == bytes)
    }

    @Test func emptyDuplicateAndInvalidRevisionFail() throws {
        for rows in try [[], [item(), item()]] {
            #expect(throws: ReturnUninvoicedItemsFailure.invalidSelection) {
                try ReturnUninvoicedItemsPayload(projectId: .init(validating: "project"), items: rows)
            }
        }
        for revision: Int64 in [0, -1, Int64.max] {
            #expect(throws: ReturnUninvoicedItemsFailure.invalidRevision) { try item(revision: revision) }
        }
    }

    @Test func storedIntentIsRevalidated() throws {
        let json = String(decoding: try OperationContractCodec.encode(command()), as: UTF8.self)
        for (before, after) in [("return-uninvoiced-items-v1", "inventory-sale-v1"),
                                ("9223372036854775806", "0"),
                                ("inventory-placement", "project-placement")] {
            #expect(throws: (any Error).self) {
                try OperationContractCodec.decode(ReturnUninvoicedItemsCommand.self,
                    from: Data(json.replacingOccurrences(of: before, with: after).utf8))
            }
        }
    }
}
