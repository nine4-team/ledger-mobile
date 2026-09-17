import Testing
@testable import LedgerTargetMigrationCore

@Suite("Current source placement evidence")
struct FirebaseCurrentItemPlacementTests {
    private func doc(_ collection: String, _ id: String, _ fields: [String: FirebaseSourceValue]) -> FirebaseSourceDocument {
        .init(accountScopeID: "account", documentPathSegments: ["accounts", "account", collection, id], entityCode: collection,
            evidenceKind: .record, fields: .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!) }), sourceRecordID: id)
    }
    @Test func matchesProjectAndSpaceWithoutInferringMovementTime() {
        let item = doc("items", "item", ["projectId": .string("project"), "spaceId": .string("space")])
        let project = doc("projects", "project", [:])
        let space = doc("spaces", "space", ["projectId": .string("project")])
        let result = FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [project, space])
        #expect(result.isResolved)
        #expect(result.source == item)
        #expect(result.projectID == "project")
        #expect(result.spaceID == "space")
    }
    @Test func unknownIsNotInventoryAndForeignSpaceIsNotAccepted() {
        #expect(!FirebaseCurrentItemPlacement.read(doc("items", "item", [:]), accountID: "account", documents: []).isResolved)
        #expect(FirebaseCurrentItemPlacement.read(doc("items", "item", ["projectId": .null]), accountID: "account", documents: []).isResolved)
        let item = doc("items", "item", ["projectId": .null, "spaceId": .string("space")])
        let space = doc("spaces", "space", ["projectId": .string("project")])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [space]).issues == ["space_scope_conflict"])
    }
    @Test func embeddedProjectAccountConflictIsUnresolved() {
        let item = doc("items", "item", ["projectId": .string("project")])
        let project = doc("projects", "project", ["accountId": .string("other")])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [project]).issues == ["unresolved_project"])
    }

    @Test func sourceIdentifiersRequireExactBytes() {
        let composed = "caf\u{00e9}"
        let decomposed = "cafe\u{0301}"
        // Equal as Swift Strings, but different source document identifiers.
        #expect(composed == decomposed)
        let item = doc("items", "item", ["projectId": .string(composed), "spaceId": .string("space")])
        let project = doc("projects", composed, [:])
        let wrongProject = doc("projects", decomposed, [:])
        let space = doc("spaces", "space", ["projectId": .string(composed)])
        let wrongScopeSpace = doc("spaces", "space", ["projectId": .string(decomposed)])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [wrongProject, space])
            .issues == ["unresolved_project"])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [project, wrongScopeSpace])
            .issues == ["space_scope_conflict"])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [project, wrongProject, space])
            .isResolved)

        func scopedItem(account: String, pathAccount: String, embeddedAccount: String) -> FirebaseSourceDocument {
            .init(accountScopeID: account, documentPathSegments: ["accounts", pathAccount, "items", "item"],
                  entityCode: "items", evidenceKind: .record,
                  fields: .map([.init(key: "accountId", value: .string(embeddedAccount)),
                                .init(key: "projectId", value: .null)]), sourceRecordID: "item")
        }
        for candidate in [scopedItem(account: decomposed, pathAccount: composed, embeddedAccount: composed),
                          scopedItem(account: composed, pathAccount: decomposed, embeddedAccount: composed),
                          scopedItem(account: composed, pathAccount: composed, embeddedAccount: decomposed)] {
            #expect(!FirebaseCurrentItemPlacement.read(candidate, accountID: composed, documents: []).isResolved)
        }
        #expect(FirebaseCurrentItemPlacement.read(
            scopedItem(account: composed, pathAccount: composed, embeddedAccount: composed),
            accountID: composed, documents: []).isResolved)
    }

    @Test func spaceReferencesAndParentAccountsRequireExactBytes() {
        let composed = "caf\u{00e9}", decomposed = "cafe\u{0301}"
        let item = doc("items", "item", ["projectId": .null, "spaceId": .string(composed)])
        let space = doc("spaces", composed, ["projectId": .null])
        let otherSpace = doc("spaces", decomposed, ["projectId": .null])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [otherSpace])
            .issues == ["unresolved_space"])
        #expect(FirebaseCurrentItemPlacement.read(item, accountID: "account", documents: [space, otherSpace])
            .isResolved)

        func scoped(_ collection: String, _ id: String, account: String, pathAccount: String,
                    embeddedAccount: String) -> FirebaseSourceDocument {
            .init(accountScopeID: account, documentPathSegments: ["accounts", pathAccount, collection, id],
                  entityCode: collection, evidenceKind: .record,
                  fields: .map([.init(key: "accountId", value: .string(embeddedAccount)),
                                .init(key: "projectId", value: .null),
                                .init(key: "spaceId", value: .string("space"))]), sourceRecordID: id)
        }
        let scopedItem = scoped("items", "item", account: composed, pathAccount: composed, embeddedAccount: composed)
        for parent in [scoped("spaces", "space", account: decomposed, pathAccount: composed, embeddedAccount: composed),
                       scoped("spaces", "space", account: composed, pathAccount: decomposed, embeddedAccount: composed),
                       scoped("spaces", "space", account: composed, pathAccount: composed, embeddedAccount: decomposed)] {
            #expect(FirebaseCurrentItemPlacement.read(scopedItem, accountID: composed, documents: [parent])
                .issues == ["unresolved_space"])
        }
        #expect(FirebaseCurrentItemPlacement.read(scopedItem, accountID: composed,
            documents: [scoped("spaces", "space", account: composed, pathAccount: composed, embeddedAccount: composed)])
            .isResolved)
    }
}
