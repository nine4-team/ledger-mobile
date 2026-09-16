import Testing
@testable import LedgerTargetMigrationCore

@Suite("Explicit reviewed Furnishings source identity")
struct FirebaseReviewedFurnishingsSourceTests {
    private func source(id: String = "reviewed", account: String = "account",
                        scope: String = "account", kind: String = "itemized",
                        name: String = "Renamed category") -> FirebaseSourceDocument {
        .init(accountScopeID: scope,
              documentPathSegments: ["accounts", account, "presets", "default", "budgetCategories", id],
              entityCode: "budget_category", evidenceKind: .record,
              fields: .map([
                .init(key: "metadata", value: .map([.init(key: "categoryType", value: .string(kind))])),
                .init(key: "name", value: .string(name))
              ]), sourceRecordID: "category-evidence")
    }
    private func matches(_ sources: [FirebaseSourceDocument]) -> Bool {
        FirebaseReviewedFurnishingsSource.matches(sources, accountID: "account", categoryID: "reviewed")
    }
    @Test func preservesIdentityAfterRename() {
        #expect(matches([source(), source(id: "additional", name: "Furnishings")]))
    }
    @Test func rejectsMissingDuplicateForeignAndChangedSources() {
        #expect(!matches([]))
        #expect(!matches([source(), source()]))
        #expect(!matches([source(account: "foreign")]))
        #expect(!matches([source(scope: "foreign")]))
        #expect(!matches([source(kind: "general")]))
        #expect(!matches([source(kind: "fee")]))
        #expect(!matches([source(id: "different", name: "Furnishings")]))
    }
}
