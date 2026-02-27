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
    s.name = name
    s.checklists = checklists
    // Space.id is @DocumentID — set via a mutable var after init
    // We work around this by using a custom approach below
    return withId(s, id: id)
}

/// Sets the @DocumentID id on a Space (which is read-only through Codable).
private func withId(_ space: Space, id: String) -> Space {
    var s = space
    // @DocumentID allows direct assignment
    s.id = id
    return s
}

private func makeChecklist(
    name: String = "Checklist",
    items: [ChecklistItem] = []
) -> Checklist {
    Checklist(name: name, items: items)
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

@Suite("Space List Calculation Tests")
struct SpaceListCalculationTests {

    // MARK: - computeChecklistProgress

    @Test("Progress with no checklists returns 0/0")
    func progressZeroItems() {
        let space = makeSpace(name: "Empty", checklists: nil)
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 0)
        #expect(progress.total == 0)
        #expect(progress.fraction == 0)
        #expect(progress.displayText == "0 of 0")
    }

    @Test("Progress with empty checklist array returns 0/0")
    func progressEmptyChecklistArray() {
        let space = makeSpace(name: "Empty Array", checklists: [])
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 0)
        #expect(progress.total == 0)
    }

    @Test("Progress with all incomplete items returns 0/N")
    func progressAllIncomplete() {
        let items = [
            makeChecklistItem(text: "A", isChecked: false),
            makeChecklistItem(text: "B", isChecked: false),
            makeChecklistItem(text: "C", isChecked: false),
        ]
        let space = makeSpace(name: "All Incomplete", checklists: [makeChecklist(items: items)])
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 0)
        #expect(progress.total == 3)
        #expect(progress.fraction == 0)
        #expect(progress.displayText == "0 of 3")
    }

    @Test("Progress with all complete items returns N/N")
    func progressAllComplete() {
        let items = [
            makeChecklistItem(text: "A", isChecked: true),
            makeChecklistItem(text: "B", isChecked: true),
            makeChecklistItem(text: "C", isChecked: true),
        ]
        let space = makeSpace(name: "All Complete", checklists: [makeChecklist(items: items)])
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 3)
        #expect(progress.total == 3)
        #expect(progress.fraction == 1.0)
        #expect(progress.displayText == "3 of 3")
    }

    @Test("Progress with partial completion returns correct values")
    func progressPartial() {
        let items = [
            makeChecklistItem(text: "A", isChecked: true),
            makeChecklistItem(text: "B", isChecked: true),
            makeChecklistItem(text: "C", isChecked: false),
            makeChecklistItem(text: "D", isChecked: false),
        ]
        let space = makeSpace(name: "Partial", checklists: [makeChecklist(items: items)])
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 2)
        #expect(progress.total == 4)
        #expect(progress.fraction == 0.5)
        #expect(progress.displayText == "2 of 4")
    }

    @Test("Progress across multiple checklists sums all items")
    func progressAcrossMultipleChecklists() {
        let checklist1 = makeChecklist(name: "CL1", items: [
            makeChecklistItem(text: "A", isChecked: true),
            makeChecklistItem(text: "B", isChecked: true),
        ])
        let checklist2 = makeChecklist(name: "CL2", items: [
            makeChecklistItem(text: "C", isChecked: true),
            makeChecklistItem(text: "D", isChecked: false),
        ])
        let space = makeSpace(name: "Multi", checklists: [checklist1, checklist2])
        let progress = SpaceListCalculations.computeChecklistProgress(for: space)
        #expect(progress.completed == 3)
        #expect(progress.total == 4)
        #expect(progress.displayText == "3 of 4")
    }

    // MARK: - buildSpaceCards

    @Test("buildSpaceCards computes item counts per space")
    func itemCountBySpaceId() {
        let spaces = [
            makeSpace(id: "s1", name: "Space 1"),
            makeSpace(id: "s2", name: "Space 2"),
        ]
        let items = [
            makeItem(spaceId: "s1", name: "Item A"),
            makeItem(spaceId: "s1", name: "Item B"),
            makeItem(spaceId: "s2", name: "Item C"),
            makeItem(spaceId: "other", name: "Item D"),
        ]
        let cards = SpaceListCalculations.buildSpaceCards(spaces: spaces, items: items)
        #expect(cards.count == 2)
        #expect(cards[0].itemCount == 2)
        #expect(cards[1].itemCount == 1)
    }

    @Test("buildSpaceCards with no matching items returns zero counts")
    func itemCountZero() {
        let spaces = [makeSpace(id: "s1", name: "Lonely Space")]
        let items = [makeItem(spaceId: "other", name: "Elsewhere")]
        let cards = SpaceListCalculations.buildSpaceCards(spaces: spaces, items: items)
        #expect(cards[0].itemCount == 0)
    }

    // MARK: - applySearch

    @Test("Search matches space name case-insensitively")
    func searchBySpaceName() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "Living Room"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(name: "Kitchen"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.applySearch(spaces: cards, query: "kitchen")
        #expect(result.count == 1)
        #expect(result[0].space.name == "Kitchen")
    }

    @Test("Empty search query returns all cards")
    func searchEmptyReturnsAll() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "A"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(name: "B"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.applySearch(spaces: cards, query: "")
        #expect(result.count == 2)
    }

    @Test("Whitespace-only search returns all cards")
    func searchWhitespaceReturnsAll() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "A"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.applySearch(spaces: cards, query: "   ")
        #expect(result.count == 1)
    }

    @Test("No match returns empty")
    func searchNoMatch() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "Kitchen"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.applySearch(spaces: cards, query: "garage")
        #expect(result.isEmpty)
    }

    // MARK: - sortSpaces

    @Test("Sorts spaces alphabetically by name")
    func sortAlphabetical() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "Zebra"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(name: "Apple"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(name: "Mango"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.sortSpaces(cards)
        #expect(result.map(\.space.name) == ["Apple", "Mango", "Zebra"])
    }

    @Test("Sort is case-insensitive")
    func sortCaseInsensitive() {
        let cards = [
            SpaceCardData(space: makeSpace(name: "banana"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(name: "Apple"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.sortSpaces(cards)
        #expect(result.map(\.space.name) == ["Apple", "banana"])
    }

    @Test("Empty names sort last")
    func sortEmptyNamesLast() {
        let cards = [
            SpaceCardData(space: makeSpace(id: "z", name: ""), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
            SpaceCardData(space: makeSpace(id: "a", name: "Has Name"), itemCount: 0, checklistProgress: ChecklistProgress(completed: 0, total: 0)),
        ]
        let result = SpaceListCalculations.sortSpaces(cards)
        #expect(result.map(\.space.name) == ["Has Name", ""])
    }
}
