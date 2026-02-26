import Foundation
import Testing
@testable import LedgeriOS

@Suite("Selection Calculation Tests")
struct SelectionCalculationTests {

    // MARK: - selectAllToggle

    @Test("Select all when none selected")
    func selectAllFromNone() {
        let result = SelectionCalculations.selectAllToggle(
            selectedIds: [],
            allIds: ["a", "b", "c"]
        )
        #expect(result == Set(["a", "b", "c"]))
    }

    @Test("Deselect all when all selected")
    func deselectAllWhenAllSelected() {
        let result = SelectionCalculations.selectAllToggle(
            selectedIds: ["a", "b", "c"],
            allIds: ["a", "b", "c"]
        )
        #expect(result.isEmpty)
    }

    @Test("Select all when partially selected")
    func selectAllFromPartial() {
        let result = SelectionCalculations.selectAllToggle(
            selectedIds: ["a"],
            allIds: ["a", "b", "c"]
        )
        #expect(result == Set(["a", "b", "c"]))
    }

    @Test("Select all with empty allIds returns empty")
    func selectAllEmptyIds() {
        let result = SelectionCalculations.selectAllToggle(
            selectedIds: ["a"],
            allIds: []
        )
        #expect(result.isEmpty)
    }

    // MARK: - isAllSelected

    @Test("All selected returns true")
    func isAllSelectedTrue() {
        let result = SelectionCalculations.isAllSelected(
            selectedIds: ["a", "b", "c"],
            allIds: ["a", "b", "c"]
        )
        #expect(result == true)
    }

    @Test("Partial selected returns false")
    func isAllSelectedPartial() {
        let result = SelectionCalculations.isAllSelected(
            selectedIds: ["a"],
            allIds: ["a", "b", "c"]
        )
        #expect(result == false)
    }

    @Test("Empty allIds returns false")
    func isAllSelectedEmpty() {
        let result = SelectionCalculations.isAllSelected(
            selectedIds: ["a"],
            allIds: []
        )
        #expect(result == false)
    }

    @Test("None selected returns false")
    func isAllSelectedNone() {
        let result = SelectionCalculations.isAllSelected(
            selectedIds: [],
            allIds: ["a", "b"]
        )
        #expect(result == false)
    }

    // MARK: - selectedCount

    @Test("Selected count returns set size")
    func selectedCountBasic() {
        #expect(SelectionCalculations.selectedCount(["a", "b", "c"]) == 3)
    }

    @Test("Selected count empty returns zero")
    func selectedCountEmpty() {
        #expect(SelectionCalculations.selectedCount([]) == 0)
    }

    // MARK: - totalCentsForSelected

    @Test("Sum cents for selected items")
    func totalCentsPartial() {
        let items: [(id: String, cents: Int)] = [
            (id: "a", cents: 100),
            (id: "b", cents: 250),
            (id: "c", cents: 50),
        ]
        let result = SelectionCalculations.totalCentsForSelected(
            selectedIds: ["a", "c"],
            items: items
        )
        #expect(result == 150)
    }

    @Test("Sum cents with none selected returns zero")
    func totalCentsNone() {
        let items: [(id: String, cents: Int)] = [
            (id: "a", cents: 100),
        ]
        let result = SelectionCalculations.totalCentsForSelected(
            selectedIds: [],
            items: items
        )
        #expect(result == 0)
    }

    @Test("Sum cents with all selected returns total")
    func totalCentsAll() {
        let items: [(id: String, cents: Int)] = [
            (id: "a", cents: 100),
            (id: "b", cents: 200),
        ]
        let result = SelectionCalculations.totalCentsForSelected(
            selectedIds: ["a", "b"],
            items: items
        )
        #expect(result == 300)
    }

    // MARK: - selectionLabel

    @Test("Selection label formats correctly")
    func selectionLabelBasic() {
        let result = SelectionCalculations.selectionLabel(count: 3, total: 10)
        #expect(result == "3 of 10 selected")
    }

    @Test("Selection label with zero count")
    func selectionLabelZero() {
        let result = SelectionCalculations.selectionLabel(count: 0, total: 5)
        #expect(result == "0 of 5 selected")
    }
}
