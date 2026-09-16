import Foundation
import Testing
@testable import LedgerTargetCore

struct EditUncollectedItemPriceCommandTests {
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
