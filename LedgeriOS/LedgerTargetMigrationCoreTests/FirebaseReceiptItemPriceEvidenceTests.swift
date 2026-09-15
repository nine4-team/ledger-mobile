import Testing
@testable import LedgerTargetMigrationCore

@Suite("Source receipt Item price evidence")
struct FirebaseReceiptItemPriceEvidenceTests {
    private func item(_ values: [String: FirebaseSourceValue]) -> FirebaseSourceDocument {
        var fields = values
        fields["transactionId"] = fields["transactionId"] ?? .string("receipt")
        return .init(accountScopeID: "account", documentPathSegments: ["accounts", "account", "items", "item"], entityCode: "items",
            evidenceKind: .record, fields: .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) }), sourceRecordID: "item")
    }
    @Test func retainsExactIndependentAmountsWithoutQuantityOrTaxInference() {
        let source = item(["purchasePriceCents": .integer("9007199254740993"), "taxAmountPurchasePriceCents": .integer("23"),
            "projectPriceCents": .integer("999"), "quantity": .integer("10"), "taxRatePct": .integer("8")])
        let result = FirebaseReceiptItemPriceEvidence.read(source, sourceAccountID: "account", sourceTransactionID: "receipt")
        #expect(result.source == source)
        #expect(result.purchasePriceCents == 9007199254740993)
        #expect(result.explicitlyRecordedTaxCents == 23)
        #expect(result.issues.isEmpty)
    }
    @Test func missingPriceDoesNotFallBackToBillingPriceOrZero() {
        let result = FirebaseReceiptItemPriceEvidence.read(item(["projectPriceCents": .integer("100")]), sourceAccountID: "account", sourceTransactionID: "receipt")
        #expect(result.purchasePriceCents == nil)
        #expect(result.explicitlyRecordedTaxCents == nil)
        #expect(result.issues == ["missing_purchasePriceCents"])
    }
    @Test func historicalOrForeignLinkCannotBorrowCurrentPrice() {
        for (account, transaction) in [("other", "receipt"), ("account", "old-receipt")] {
            let result = FirebaseReceiptItemPriceEvidence.read(item(["purchasePriceCents": .integer("100")]), sourceAccountID: account, sourceTransactionID: transaction)
            #expect(result.purchasePriceCents == nil)
            #expect(!result.issues.isEmpty)
        }
    }
    @Test func explicitZeroSurvivesAndDoubleIsNotRounded() {
        #expect(FirebaseReceiptItemPriceEvidence.read(item(["purchasePriceCents": .integer("0")]), sourceAccountID: "account", sourceTransactionID: "receipt").purchasePriceCents == 0)
        #expect(FirebaseReceiptItemPriceEvidence.read(item(["purchasePriceCents": .double(bits: "3ff0000000000000")]), sourceAccountID: "account", sourceTransactionID: "receipt").purchasePriceCents == nil)
    }
}
