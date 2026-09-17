import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Paid Item return intent")
struct ReturnPaidItemsCommandTests {
    private func item() throws -> ReturnPaidItemsPayload.Item {
        try .init(itemId: .init(validating: "item"), placementId: .init(validating: "project-placement"),
            chargeId: .init(validating: "sale-charge"), paidInvoiceLineId: .init(validating: "paid-line"),
            inventoryPlacementId: .init(validating: "inventory-placement"),
            returnOccurrenceId: .init(validating: "return-occurrence"), creditId: .init(validating: "credit"))
    }

    private func command() throws -> ReturnPaidItemsCommand {
        try .init(operationId: .init(validating: "return-operation"), accountId: .init(validating: "account"),
            actorPrincipalId: .init(validating: "actor"), capturedAt: Date(timeIntervalSince1970: 1000.125),
            payload: .init(projectId: .init(validating: "project"), items: [item()]))
    }

    @Test func frozenSourceAndSuccessorIdentitiesSurviveReplay() throws {
        let original = try command(), bytes = try OperationContractCodec.encode(original)
        let restored = try OperationContractCodec.decode(ReturnPaidItemsCommand.self, from: bytes)
        #expect(restored.envelope.payload == original.envelope.payload)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.envelope.payload.items[0].paidInvoiceLineId.rawValue == "paid-line")
    }

    @Test func duplicateEmptyAndOversizedSelectionsFail() throws {
        for rows in try [[], [item(), item()], Array(repeating: item(), count: 101)] {
            #expect(throws: ReturnPaidItemsFailure.invalidSelection) {
                try ReturnPaidItemsPayload(projectId: .init(validating: "project"), items: rows)
            }
        }
    }

    @Test func persistedIntentCannotBypassValidation() throws {
        let json = String(decoding: try OperationContractCodec.encode(command()), as: UTF8.self)
        for (before, after) in [("return-paid-items-v1", "return-uninvoiced-items-v1"),
                                ("inventory-placement", "project-placement")] {
            #expect(throws: (any Error).self) {
                try OperationContractCodec.decode(ReturnPaidItemsCommand.self,
                    from: Data(json.replacingOccurrences(of: before, with: after).utf8))
            }
        }
    }

    @Test func reviewUsesFrozenBasisAndMintsDistinctReturnIdentities() throws {
        let source = try item()
        let row = try PaidReturnReview.Item(itemId: source.itemId, placementId: source.placementId,
            chargeId: source.chargeId, paidInvoiceLineId: source.paidInvoiceLineId,
            paidAmount: .init(minorUnits: Int64.max, currency: .init(validating: "USD")),
            categoryId: .init(validating: "category"))
        let review = try PaidReturnReview(accountId: .init(validating: "account"), principalId: .init(validating: "actor"),
            projectId: .init(validating: "project"), items: [row])
        let payload = try review.makePayload()
        #expect(payload.items[0].paidInvoiceLineId == source.paidInvoiceLineId)
        #expect(payload.items[0].inventoryPlacementId != source.placementId)
        #expect(payload.items[0].creditId != payload.items[0].returnOccurrenceId)
        #expect(review.items[0].paidAmount.minorUnits == Int64.max)
        #expect(throws: ReturnPaidItemsFailure.invalidSelection) {
            try PaidReturnReview(accountId: review.accountId, principalId: review.principalId,
                projectId: review.projectId, items: [row, row])
        }
        #expect(throws: ReturnPaidItemsFailure.invalidSelection) {
            try PaidReturnReview.Item(itemId: source.itemId, placementId: source.placementId,
                chargeId: source.chargeId, paidInvoiceLineId: source.paidInvoiceLineId,
                paidAmount: .init(minorUnits: 0, currency: .init(validating: "USD")), categoryId: row.categoryId)
        }
    }
}
