import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Inventory return to proven source")
struct InventorySourceReturnReviewTests {
    private func item(_ suffix: String, project: String = "kristen", amount: Int64 = 100,
                      category: String = "furnishings", currency: String = "USD") throws -> InventorySourceReturnReview.Item {
        try .init(itemId: .init(validating: "item-" + suffix),
                  placementId: .init(validating: "inventory-" + suffix),
                  inventoryEntryId: .init(validating: "entry-" + suffix),
                  sourceProjectId: .init(validating: project),
                  sourceCategoryId: .init(validating: category),
                  sourceAmount: Money(minorUnits: amount, currency: .init(validating: currency)))
    }
    private func review(_ items: [InventorySourceReturnReview.Item]) throws -> InventorySourceReturnReview {
        try .init(accountId: .init(validating: "account"), principalId: .init(validating: "principal"), items: items)
    }

    @Test func sourceLockedBulkPreservesEachFrozenBasisAndRetryIdentity() throws {
        let first = try item("a", amount: 9_007_199_254_740_993, category: "original-a")
        let second = try item("b", amount: 123, category: "original-b")
        let value = try review([first, second])
        #expect(value.projectId.rawValue == "kristen")
        #expect(value.items.map(\.sourceAmount.minorUnits) == [9_007_199_254_740_993, 123])
        #expect(value.items.map(\.sourceCategoryId.rawValue) == ["original-a", "original-b"])
        let payload = try value.makePayload()
        let bytes = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(ReturnInventoryItemsToSourcePayload.self, from: bytes) == payload)
        #expect(payload.items.map(\.inventoryEntryId) == value.items.map(\.inventoryEntryId))
        #expect(payload.items.map(\.placementId) == value.items.map(\.placementId))
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let rows = try #require(object["items"] as? [[String: Any]])
        #expect(rows.allSatisfy { Set($0.keys) == ["itemId", "placementId", "inventoryEntryId", "projectPlacementId", "occurrenceId"] })
    }

    @Test func mixedOrMissingEvidenceDoesNotInventCommonReturn() throws {
        let first = try item("a"), other = try item("b", project: "mason")
        #expect(throws: InventorySourceReturnReview.Failure.mixedSourceProjects) { try review([first, other]) }
        #expect(throws: InventorySourceReturnReview.Failure.invalidSelection) { try review([]) }
        #expect(throws: InventorySourceReturnReview.Failure.invalidSelection) { try review([first, first]) }
        #expect(throws: InventorySourceReturnReview.Failure.invalidBasis) { try item("free", amount: -1) }
        let foreignCurrency = try item("c", currency: "EUR")
        #expect(throws: InventorySourceReturnReview.Failure.invalidBasis) { try review([first, foreignCurrency]) }
    }

    @Test func saleRemainsIndependentAndUsesNewDestinationPrice() throws {
        let source = try review([item("a")])
        let usd = try CurrencyCode(validating: "USD")
        let sale = try InventorySaleReview(accountId: source.accountId, principalId: source.principalId,
            items: source.items.map { .init(itemId: $0.itemId, placementId: $0.placementId, priceRevision: 1,
                projectPrice: .known(Money(minorUnits: 999, currency: usd)),
                purchaseCost: .known($0.sourceAmount)) })
        let salePayload = try sale.makePayload(projectId: .init(validating: "mason"), currency: usd, enteredPrices: [:])
        #expect(salePayload.projectId.rawValue == "mason")
        #expect(salePayload.items.first?.reviewedPriceMinorUnits == "999")
        #expect(try source.makePayload().projectId.rawValue == "kristen")
        #expect(source.items.first?.sourceAmount.minorUnits == 100)
        // No return review or source Project is an input to the existing sale.
        #expect(try sale.makePayload(projectId: .init(validating: "another"), currency: usd, enteredPrices: [:])
            .projectId.rawValue == "another")
    }

    @Test func restoredPayloadRejectsDuplicateAndReusedPlacementIdentities() throws {
        let payload = try review([item("a")]).makePayload()
        let bytes = try JSONEncoder().encode(payload)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var rows = try #require(object["items"] as? [[String: Any]])
        object["items"] = [rows[0], rows[0]]
        let duplicates = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: InventorySourceReturnReview.Failure.invalidSelection) {
            try JSONDecoder().decode(ReturnInventoryItemsToSourcePayload.self, from: duplicates)
        }
        rows[0]["projectPlacementId"] = rows[0]["placementId"]
        object["items"] = rows
        let reused = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: InventorySourceReturnReview.Failure.invalidSelection) {
            try JSONDecoder().decode(ReturnInventoryItemsToSourcePayload.self, from: reused)
        }
    }

    @Test func savedCommandRetainsExactIntentAndRejectsWrongContract() throws {
        let source = try review([item("a")])
        let original = try ReturnInventoryItemsToSourceCommand(
            operationId: .init(validating: "source-return-operation"), accountId: source.accountId,
            actorPrincipalId: source.principalId, capturedAt: Date(timeIntervalSince1970: 1000.125),
            payload: source.makePayload())
        let bytes = try OperationContractCodec.encode(original)
        let restored = try OperationContractCodec.decode(ReturnInventoryItemsToSourceCommand.self, from: bytes)
        #expect(restored.envelope.payload == original.envelope.payload)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        let corrupted = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "return-inventory-to-source-v1", with: "return-paid-items-v1")
        #expect(throws: ReturnInventoryItemsToSourceCommand.Failure.self) {
            try OperationContractCodec.decode(ReturnInventoryItemsToSourceCommand.self, from: Data(corrupted.utf8))
        }
        #expect(throws: ReturnInventoryItemsToSourceCommand.Failure.self) {
            try ReturnInventoryItemsToSourceCommand(operationId: original.envelope.operationId,
                accountId: source.accountId, actorPrincipalId: source.principalId,
                capturedAt: Date(timeIntervalSince1970: -1), payload: original.envelope.payload)
        }
    }
}
