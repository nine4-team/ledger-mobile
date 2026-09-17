import Foundation
import Testing
@testable import LedgerTargetCore

struct EditUncollectedItemPriceCommandTests {
    @Test func clearedPriceRetainsCurrencyIdentity() throws {
        let eur = try CurrencyCode(validating: "EUR"), usd = try CurrencyCode(validating: "USD")
        let review = try ItemPriceEditReview(inventoryItemId: .init(validating: "item"),
            placementId: .init(validating: "placement"), priceRevision: 2, currentPrice: nil,
            purchaseCost: .confirmedAbsent, priceCurrency: eur)
        #expect(try review.clearingInventoryPrice(currency: eur).reviewedPrice.currency == eur)
        #expect(throws: InventorySalePrice.Failure.currencyMismatch) {
            try review.payload(requested: .init(minorUnits: 100, currency: usd))
        }
        #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidPrice) {
            try review.clearingInventoryPrice(currency: usd)
        }
    }
    @Test func inventoryReviewNormalizesClearAndRetainsRevision() throws {
        let usd = try CurrencyCode(validating: "USD")
        for cost in [InventorySalePrice.Evidence.confirmedAbsent, .known(.init(minorUnits: 150, currency: usd))] {
            let review = try ItemPriceEditReview(inventoryItemId: .init(validating: "item"),
                placementId: .init(validating: "placement"), priceRevision: 7,
                currentPrice: nil, purchaseCost: cost)
            let clear = try review.clearingInventoryPrice(currency: usd)
            #expect(clear.clearPrice == true && clear.expectedPriceRevision == 7)
            #expect(clear.reviewedPrice.minorUnits == (cost == .confirmedAbsent ? 0 : 150))
            let zero = try review.payload(requested: .init(minorUnits: 0, currency: usd))
            #expect(zero.clearPrice == false)
            #expect(zero.reviewedPrice == clear.reviewedPrice)
        }
        #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidRevision) {
            try ItemPriceEditReview(inventoryItemId: .init(validating: "item"),
                placementId: .init(validating: "placement"), priceRevision: 0,
                currentPrice: nil, purchaseCost: .unavailable)
        }
    }
    @Test func inventoryIntentKeepsZeroClearAndChargeIdentityDistinct() throws {
        let zero = Money(minorUnits: 0, currency: try .init(validating: "USD"))
        for clear in [false, true] {
            let payload = try EditUncollectedItemPriceCommand.Payload(
                inventoryItemId: .init(validating: "item"), placementId: .init(validating: "placement"),
                expectedPriceRevision: 2, requestedPrice: zero, reviewedPrice: zero, clearPrice: clear)
            let command = try EditUncollectedItemPriceCommand(operationId: .init(validating: "inventory-price"),
                accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
                capturedAt: Date(timeIntervalSince1970: 100), payload: payload)
            #expect(command.envelope.contractVersion.rawValue == "item-inventory-price-edit-v2")
            let bytes = try OperationContractCodec.encode(command)
            let restored = try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self, from: bytes)
            #expect(restored.envelope.payload == payload)
            #expect(restored.envelope.payload.projectId == nil)
            #expect(restored.envelope.payload.occurrenceId == nil)
            #expect(restored.envelope.payload.clearPrice == clear)
            let malformed = String(decoding: bytes, as: UTF8.self)
                .replacingOccurrences(of: "item-inventory-price-edit-v2", with: "item-uncollected-price-edit-v1")
            #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidEnvelope) {
                try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self, from: Data(malformed.utf8))
            }
        }
    }
    private func payload(priceRevision: Int64 = 1, chargeRevision: Int64 = 1,
                         requested: Int64 = 100, reviewed: Int64 = 200) throws -> EditUncollectedItemPriceCommand.Payload {
        try .init(projectId: .init(validating: "project"), itemId: .init(validating: "item"),
            placementId: .init(validating: "placement"), occurrenceId: .init(validating: "charge"),
            expectedPriceRevision: priceRevision, expectedChargeRevision: chargeRevision,
            requestedPrice: .init(minorUnits: requested, currency: .init(validating: "USD")),
            reviewedPrice: .init(minorUnits: reviewed, currency: .init(validating: "USD")))
    }

    @Test func retainsExactIntentAndIdentityAcrossSerialization() throws {
        let value = try EditUncollectedItemPriceCommand(operationId: .init(validating: "price-edit"),
            accountId: .init(validating: "account"), actorPrincipalId: .init(validating: "actor"),
            capturedAt: Date(timeIntervalSince1970: 100),
            payload: payload(requested: Int64.max, reviewed: Int64.max))
        let data = try OperationContractCodec.encode(value)
        let restored = try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self, from: data)
        #expect(restored.envelope.payload == value.envelope.payload)
        #expect(restored.envelope.operationId == value.envelope.operationId)
        #expect(try OperationContractCodec.encode(restored) == data)
        let malformed = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"expectedChargeRevision\":1", with: "\"expectedChargeRevision\":0")
        #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidRevision) {
            try OperationContractCodec.decode(EditUncollectedItemPriceCommand.self, from: Data(malformed.utf8))
        }
    }

    @Test func validatesRevisionsAndReviewedNormalizationWithoutInventingCost() throws {
        #expect(try payload(priceRevision: 0, requested: 0).reviewedPrice.minorUnits == 200)
        for revision in [-1, Int64.max] {
            #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidRevision) { try payload(priceRevision: revision) }
        }
        for revision in [0, Int64.max] {
            #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidRevision) { try payload(chargeRevision: revision) }
        }
        for (requested, reviewed): (Int64, Int64) in [(-1, 200), (200, 100), (0, 0)] {
            #expect(throws: EditUncollectedItemPriceCommand.Failure.invalidPrice) {
                try payload(requested: requested, reviewed: reviewed)
            }
        }
    }
}
