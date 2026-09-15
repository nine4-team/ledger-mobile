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
}
