import Foundation
import FirebaseFirestore
import Testing
@testable import LedgeriOS

@Suite("Space CRUD — Emulator Integration", .tags(.integration))
struct SpaceCRUDIntegrationTests {
    let accountId = FirestoreTestHelper.testAccountId
    var spacesPath: String { FirestoreTestHelper.spacesPath(accountId: accountId) }

    // MARK: - Nested Struct Round-Trip

    @Test("Space with nested checklists — full hierarchy survives round-trip")
    func nestedChecklistRoundTrip() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let space = makeSpace(
            id: id,
            projectId: "proj1",
            name: "Living Room",
            notes: "Main living area",
            checklists: [
                Checklist(id: "cl1", name: "Furniture", items: [
                    ChecklistItem(id: "cli1", text: "Sofa", isChecked: true),
                    ChecklistItem(id: "cli2", text: "Coffee Table", isChecked: false)
                ]),
                Checklist(id: "cl2", name: "Decor", items: [
                    ChecklistItem(id: "cli3", text: "Throw Pillows", isChecked: false)
                ])
            ]
        )

        try FirestoreTestHelper.write(space, toCollection: spacesPath, id: id)
        let result: Space = try #require(await FirestoreTestHelper.read(Space.self, fromCollection: spacesPath, id: id))

        #expect(result.name == "Living Room")
        #expect(result.notes == "Main living area")
        #expect(result.projectId == "proj1")

        let checklists = try #require(result.checklists)
        #expect(checklists.count == 2)

        #expect(checklists[0].id == "cl1")
        #expect(checklists[0].name == "Furniture")
        #expect(checklists[0].items.count == 2)
        #expect(checklists[0].items[0].text == "Sofa")
        #expect(checklists[0].items[0].isChecked == true)
        #expect(checklists[0].items[1].text == "Coffee Table")
        #expect(checklists[0].items[1].isChecked == false)

        #expect(checklists[1].id == "cl2")
        #expect(checklists[1].name == "Decor")
        #expect(checklists[1].items.count == 1)
    }

    @Test("Update space notes — checklists not destroyed by partial update")
    func partialUpdatePreservesChecklists() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let space = makeSpace(
            id: id,
            name: "Kitchen",
            notes: "Original notes",
            checklists: [
                Checklist(id: "cl1", name: "Appliances", items: [
                    ChecklistItem(id: "cli1", text: "Refrigerator", isChecked: false)
                ])
            ]
        )

        try FirestoreTestHelper.write(space, toCollection: spacesPath, id: id)

        // Partial update — only change notes
        try await FirestoreTestHelper.update(
            documentPath: "\(spacesPath)/\(id)",
            fields: ["notes": "Updated notes"]
        )

        let result: Space = try #require(await FirestoreTestHelper.read(Space.self, fromCollection: spacesPath, id: id))

        #expect(result.notes == "Updated notes")
        // Checklists must survive the partial update
        let checklists = try #require(result.checklists)
        #expect(checklists.count == 1)
        #expect(checklists[0].items[0].text == "Refrigerator")
    }

    @Test("Create minimal space — only name")
    func createMinimalSpace() async throws {
        try await FirestoreTestHelper.signIn()
        let id = UUID().uuidString
        let space = makeSpace(id: id, name: "Bedroom")

        try FirestoreTestHelper.write(space, toCollection: spacesPath, id: id)
        let result: Space = try #require(await FirestoreTestHelper.read(Space.self, fromCollection: spacesPath, id: id))

        #expect(result.name == "Bedroom")
        #expect(result.notes == nil)
        #expect(result.checklists == nil)
        #expect(result.isArchived == nil)
    }
}
