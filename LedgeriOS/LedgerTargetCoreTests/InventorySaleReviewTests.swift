import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Inventory sale review response")
struct InventorySaleReviewTests {
    private let account = try! AccountID(validating: "account")
    private let principal = try! PrincipalID(validating: "member")
    private let item = try! ItemID(validating: "item")
    private let json = #"{"accountId":"account","principalId":"member","items":[{"itemId":"item","placementId":"placement","priceRevision":"1","projectPrice":{"state":"known","amountMinorUnits":"9223372036854775807","currency":"USD"},"purchaseCost":{"state":"absent"}}]}"#

    @Test func exactAmountsAndScope() throws {
        let review = try JSONDecoder().decode(InventorySaleReview.self, from: Data(json.utf8))
        try review.validate(accountId: account, principalId: principal, itemIds: [item])
        #expect(try review.items[0].reviewedPrice(currency: .init(validating: "USD")).minorUnits == Int64.max)
        #expect(throws: InventorySaleReview.Failure.scopeMismatch) {
            try review.validate(accountId: .init(validating: "foreign"), principalId: principal, itemIds: [item])
        }
        #expect(throws: InventorySaleReview.Failure.selectionMismatch) {
            try review.validate(accountId: account, principalId: principal, itemIds: [item, item])
        }
        #expect(throws: InventorySaleReview.Failure.selectionMismatch) {
            try review.validate(accountId: account, principalId: principal, itemIds: [.init(validating: "different")])
        }
    }

    @Test func unavailableCostNeverBecomesPriceEntry() throws {
        let text = json.replacingOccurrences(of: #""state":"absent""#, with: #""state":"unavailable""#)
        let review = try JSONDecoder().decode(InventorySaleReview.self, from: Data(text.utf8))
        try review.validate(accountId: account, principalId: principal, itemIds: [item])
        #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
            try review.items[0].reviewedPrice(currency: .init(validating: "USD"))
        }
    }

    @Test func malformedEvidenceIsRejected() throws {
        for text in [
            json.replacingOccurrences(of: "9223372036854775807", with: "9223372036854775808"),
            json.replacingOccurrences(of: #""9223372036854775807""#, with: "100"),
            json.replacingOccurrences(of: #""state":"absent""#, with: #""state":"absent","amountMinorUnits":"100""#),
            json.replacingOccurrences(of: #""priceRevision":"1""#, with: #""priceRevision":"0""#)
        ] {
            #expect(throws: (any Error).self) {
                let review = try JSONDecoder().decode(InventorySaleReview.self, from: Data(text.utf8))
                try review.validate(accountId: account, principalId: principal, itemIds: [item])
            }
        }
    }

    @Test func confirmationUsesReviewedPriceAndRetainsPayloadForRetry() throws {
        let review = try JSONDecoder().decode(InventorySaleReview.self, from: Data(json.utf8))
        let usd = try CurrencyCode(validating: "USD")
        let project = try ProjectID(validating: "destination")
        let payload = try review.makePayload(projectId: project, currency: usd, enteredPrices: [:])
        #expect(payload.items[0].reviewedPriceMinorUnits == String(Int64.max))
        #expect(payload.items[0].placementId.rawValue == "placement")
        #expect(payload.items[0].priceRevision == "1")
        let retained = try JSONDecoder().decode(InventorySalePayload.self, from: JSONEncoder().encode(payload))
        #expect(retained == payload)
        #expect(throws: InventorySaleReview.Failure.invalidEvidence) {
            try review.makePayload(projectId: project, currency: usd,
                enteredPrices: [item: .init(minorUnits: 1,currency: usd)])
        }
    }

    @Test func priceEntryRequiresConfirmedAbsenceNotMissingEvidence() throws {
        let usd = try CurrencyCode(validating: "USD")
        let project = try ProjectID(validating: "destination")
        func review(_ cost: InventorySalePrice.Evidence) throws -> InventorySaleReview {
            try .init(accountId: account,principalId: principal,items: [
                .init(itemId: item,placementId: .init(validating: "placement"),priceRevision: 0,
                    projectPrice: .confirmedAbsent,purchaseCost: cost)])
        }
        let absent = try review(.confirmedAbsent)
        let entered = [item: Money(minorUnits: 125,currency: usd)]
        #expect(try absent.makePayload(projectId: project,currency: usd,enteredPrices: entered).items[0].reviewedPriceMinorUnits == "125")
        #expect(throws: InventorySalePrice.Failure.priceRequired) {
            try absent.makePayload(projectId: project,currency: usd,enteredPrices: [:])
        }
        #expect(throws: InventorySalePrice.Failure.evidenceUnavailable) {
            try review(.unavailable).makePayload(projectId: project,currency: usd,enteredPrices: entered)
        }
    }
}
