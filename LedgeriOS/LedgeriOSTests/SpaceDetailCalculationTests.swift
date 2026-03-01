import Foundation
import Testing
@testable import LedgeriOS

// MARK: - Test Helpers

private func makeSpace(
    id: String = "space-1",
    name: String = "",
    checklists: [Checklist]? = nil
) -> Space {
    var s = Space()
    s.id = id
    s.name = name
    s.checklists = checklists
    return s
}

private func makeChecklistItem(text: String = "Task", isChecked: Bool = false) -> ChecklistItem {
    ChecklistItem(text: text, isChecked: isChecked)
}

private func makeItem(spaceId: String? = nil, name: String = "Item") -> Item {
    var item = Item()
    item.spaceId = spaceId
    item.name = name
    return item
}

// MARK: - Tests

@Suite("Space Detail Calculation Tests")
struct SpaceDetailCalculationTests {

    // MARK: - canSaveAsTemplate

    @Test("Owner can save as template")
    func ownerCanSaveAsTemplate() {
        #expect(SpaceDetailCalculations.canSaveAsTemplate(userRole: "owner") == true)
    }

    @Test("Admin can save as template")
    func adminCanSaveAsTemplate() {
        #expect(SpaceDetailCalculations.canSaveAsTemplate(userRole: "admin") == true)
    }

    @Test("Member cannot save as template")
    func memberCannotSaveAsTemplate() {
        #expect(SpaceDetailCalculations.canSaveAsTemplate(userRole: "member") == false)
    }

    @Test("Unknown role cannot save as template")
    func unknownRoleCannotSave() {
        #expect(SpaceDetailCalculations.canSaveAsTemplate(userRole: "viewer") == false)
    }

    @Test("Empty role cannot save as template")
    func emptyRoleCannotSave() {
        #expect(SpaceDetailCalculations.canSaveAsTemplate(userRole: "") == false)
    }

    // MARK: - itemsInSpace

    @Test("Filters items belonging to the given space")
    func itemsInSpaceFiltersCorrectly() {
        let items = [
            makeItem(spaceId: "s1", name: "A"),
            makeItem(spaceId: "s1", name: "B"),
            makeItem(spaceId: "s2", name: "C"),
            makeItem(spaceId: nil, name: "D"),
        ]
        let result = SpaceDetailCalculations.itemsInSpace(spaceId: "s1", allItems: items)
        #expect(result.count == 2)
        #expect(result.map(\.name) == ["A", "B"])
    }

    @Test("Returns empty when no items match the space")
    func itemsInSpaceNoMatch() {
        let items = [
            makeItem(spaceId: "s2", name: "C"),
        ]
        let result = SpaceDetailCalculations.itemsInSpace(spaceId: "s1", allItems: items)
        #expect(result.isEmpty)
    }

    @Test("Returns empty for empty items array")
    func itemsInSpaceEmptyInput() {
        let result = SpaceDetailCalculations.itemsInSpace(spaceId: "s1", allItems: [])
        #expect(result.isEmpty)
    }

    // MARK: - checklistProgress

    @Test("Checklist progress delegates correctly")
    func checklistProgressDelegates() {
        let checklist = Checklist(name: "CL", items: [
            makeChecklistItem(text: "A", isChecked: true),
            makeChecklistItem(text: "B", isChecked: false),
            makeChecklistItem(text: "C", isChecked: true),
        ])
        let space = makeSpace(name: "Test", checklists: [checklist])
        let progress = SpaceDetailCalculations.checklistProgress(for: space)
        #expect(progress.completed == 2)
        #expect(progress.total == 3)
    }

    // MARK: - defaultSectionStates

    @Test("Default section states match FR-9.3 spec")
    func defaultSectionStatesCorrect() {
        let states = SpaceDetailCalculations.defaultSectionStates()
        #expect(states["media"] == true)
        #expect(states["notes"] == false)
        #expect(states["items"] == false)
        #expect(states["checklists"] == false)
        #expect(states.count == 4)
    }
}
