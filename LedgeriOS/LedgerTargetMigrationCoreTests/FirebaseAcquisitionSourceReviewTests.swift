import Testing
@testable import LedgerTargetMigrationCore

@Suite("Source acquisition review")
struct FirebaseAcquisitionSourceReviewTests {
    private func source(_ extra: [String: FirebaseSourceValue] = [:]) -> FirebaseSourceDocument {
        var fields: [String: FirebaseSourceValue] = ["type": .string("Purchase"), "purchasedBy": .string("client-card"), "amountCents": .integer("9007199254740993")]
        fields.merge(extra) { _, new in new }
        return .init(accountScopeID: "account", documentPathSegments: ["accounts", "account", "transactions", "receipt"],
            entityCode: "transactions", evidenceKind: .record,
            fields: .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) }), sourceRecordID: "receipt")
    }
    @Test func exactSourceMeaningIsRetained() {
        let document = source()
        let result = FirebaseAcquisitionSourceReview.review(document, accountID: "account")
        #expect(result.source == document)
        #expect(result.canReconcileAcquisition)
        #expect(result.payer == .client)
        #expect(result.amountCents == 9007199254740993)
        #expect(FirebaseAcquisitionSourceReview.review(source(["purchasedBy": .string("design-business")]), accountID: "account").payer == .business)
    }
    @Test func neverInfersUnknownPayerOrRoundsMoney() {
        for value: FirebaseSourceValue in [.null, .string("someone"), .string("")] {
            #expect(!FirebaseAcquisitionSourceReview.review(source(["purchasedBy": value]), accountID: "account").canReconcileAcquisition)
        }
        #expect(!FirebaseAcquisitionSourceReview.review(source(["amountCents": .double(bits: "3ff0000000000000")]), accountID: "account").canReconcileAcquisition)
    }
    @Test func rejectsMovementCancellationAndCrossAccount() {
        for extra: [String: FirebaseSourceValue] in [
            ["transactionType": .string("sale")], ["isCanonicalInventorySale": .bool(true)],
            ["inventorySaleDirection": .string("to-project")], ["type": .string("Return")],
            ["isCanceled": .bool(true)], ["status": .string("canceled")], ["accountId": .string("other")]
        ] { #expect(!FirebaseAcquisitionSourceReview.review(source(extra), accountID: "account").canReconcileAcquisition) }
    }
    @Test func reconcilesBothDirectionsWithoutInventingItems() {
        let purchase = FirebaseAcquisitionSourceReview.review(source(["itemIds": .array([.string("chair")])]), accountID: "account")
        let item = FirebaseSourceDocument(accountScopeID: "account", documentPathSegments: ["accounts", "account", "items", "chair"],
            entityCode: "items", evidenceKind: .record, fields: .map([.init(key: "transactionId", value: .string("receipt"))]), sourceRecordID: "chair")
        let links = FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: [item], lineage: [])
        #expect(links.canMapCurrentMembership)
        #expect(links.declaredItemIDs == ["chair"])
        #expect(links.currentItemIDs == ["chair"])
        let missing = FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: [], lineage: [])
        #expect(missing.issues == ["missing_item", "current_membership_mismatch"])
        let empty = FirebaseAcquisitionSourceReview.review(source(["itemIds": .array([])]), accountID: "account")
        #expect(FirebaseAcquisitionSourceReview.reconcileItems(empty, documents: [item], lineage: []).issues == ["current_membership_mismatch"])
    }
    @Test func optionalLegacyListKeepsSourceAndStillChecksReverseLinks() {
        let item = FirebaseSourceDocument(accountScopeID: "account", documentPathSegments: ["accounts", "account", "items", "chair"],
            entityCode: "items", evidenceKind: .record, fields: .map([.init(key: "transactionId", value: .string("receipt"))]), sourceRecordID: "chair")
        for extra: [String: FirebaseSourceValue] in [[:], ["itemIds": .null], ["itemIds": .array([])]] {
            let document = source(extra)
            let purchase = FirebaseAcquisitionSourceReview.review(document, accountID: "account")
            #expect(purchase.source == document)
            #expect(FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: [], lineage: []).canMapCurrentMembership)
            #expect(FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: [item], lineage: []).issues == ["current_membership_mismatch"])
        }
    }
    @Test func invalidOrDuplicateListsRemainUnresolved() {
        for extra: [String: FirebaseSourceValue] in [["itemIds": .string("chair")], ["itemIds": .array([.string("chair"), .string("chair")])]] {
            let purchase = FirebaseAcquisitionSourceReview.review(source(extra), accountID: "account")
            #expect(!FirebaseAcquisitionSourceReview.reconcileItems(purchase, documents: [], lineage: []).canMapCurrentMembership)
        }
    }
}
