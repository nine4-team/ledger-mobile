import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Inventory sale command")
struct InventorySaleCommandTests {
    private func selection(amount: Int64 = Int64.max) throws -> InventorySaleSelection {
        try .init(itemId: .init(validating: "item"), placementId: .init(validating: "old"),
            priceRevision: 0, reviewedPriceMinorUnits: amount, newPlacementId: .init(validating: "new"),
            occurrenceId: .init(validating: "charge"))
    }

    private func command() throws -> InventorySaleCommand {
        try .init(operationId: .init(validating: "sale"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1000),
            payload: .init(projectId: .init(validating: "project"), currency: .init(validating: "USD"),
                           items: [selection()]))
    }

    @Test func replayRetainsExactAmountsAndIdentities() throws {
        let original = try command()
        let bytes = try OperationContractCodec.encode(original)
        let restored = try OperationContractCodec.decode(InventorySaleCommand.self, from: bytes)
        #expect(restored.envelope.payload == original.envelope.payload)
        #expect(restored.envelope.operationId == original.envelope.operationId)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.payload.items[0].reviewedPriceMinorUnits == "9223372036854775807")
    }

    @Test func rejectsEmptyDuplicateAndFreeSales() throws {
        let item = try selection()
        for rows in [[], [item, item]] {
            #expect(throws: InventorySaleCommandFailure.invalidSelection) {
                try InventorySalePayload(projectId: .init(validating: "project"),
                    currency: .init(validating: "USD"), items: rows)
            }
        }
        #expect(throws: InventorySaleCommandFailure.invalidPrice) { try selection(amount: 0) }
    }

    @Test func persistedCommandsAreRevalidated() throws {
        let bytes = try OperationContractCodec.encode(command())
        let json = String(decoding: bytes, as: UTF8.self)
        for (before, after) in [("9223372036854775807", "9223372036854775808"),
                                ("inventory-sale-v1", "inventory-sale-v2")] {
            let corrupt = Data(json.replacingOccurrences(of: before, with: after).utf8)
            #expect(throws: (any Error).self) {
                try OperationContractCodec.decode(InventorySaleCommand.self, from: corrupt)
            }
        }
    }
}
