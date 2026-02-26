import Foundation
import Testing
@testable import LedgeriOS

@Suite("Action Menu Calculation Tests")
struct ActionMenuCalculationTests {

    // MARK: - Helper factories

    private func makeItem(
        id: String = "item1",
        subactions: [ActionMenuSubitem]? = nil,
        selectedSubactionKey: String? = nil,
        isDestructive: Bool = false,
        isActionOnly: Bool = false
    ) -> ActionMenuItem {
        ActionMenuItem(
            id: id,
            label: "Test Item",
            subactions: subactions,
            selectedSubactionKey: selectedSubactionKey,
            isDestructive: isDestructive,
            isActionOnly: isActionOnly
        )
    }

    private func makeSubitem(id: String = "sub1") -> ActionMenuSubitem {
        ActionMenuSubitem(id: id, label: "Sub Item") {}
    }

    // MARK: - toggleExpansion

    @Test("Expand when nothing is expanded")
    func toggleExpansionFromNil() {
        let result = ActionMenuCalculations.toggleExpansion(currentKey: nil, tappedKey: "a")
        #expect(result == "a")
    }

    @Test("Collapse when tapping the expanded key")
    func toggleExpansionCollapse() {
        let result = ActionMenuCalculations.toggleExpansion(currentKey: "a", tappedKey: "a")
        #expect(result == nil)
    }

    @Test("Switch to different key when another is expanded")
    func toggleExpansionSwitch() {
        let result = ActionMenuCalculations.toggleExpansion(currentKey: "a", tappedKey: "b")
        #expect(result == "b")
    }

    // MARK: - isSubactionSelected

    @Test("Subaction is selected when key matches")
    func subactionSelectedMatch() {
        let item = makeItem(selectedSubactionKey: "sub1")
        #expect(ActionMenuCalculations.isSubactionSelected(item: item, subactionKey: "sub1") == true)
    }

    @Test("Subaction is not selected when key differs")
    func subactionSelectedDifferent() {
        let item = makeItem(selectedSubactionKey: "sub1")
        #expect(ActionMenuCalculations.isSubactionSelected(item: item, subactionKey: "sub2") == false)
    }

    @Test("Subaction is not selected when selectedSubactionKey is nil")
    func subactionSelectedNil() {
        let item = makeItem(selectedSubactionKey: nil)
        #expect(ActionMenuCalculations.isSubactionSelected(item: item, subactionKey: "sub1") == false)
    }

    // MARK: - hasSubactions

    @Test("Has subactions when array is non-empty")
    func hasSubactionsTrue() {
        let item = makeItem(subactions: [makeSubitem()])
        #expect(ActionMenuCalculations.hasSubactions(item) == true)
    }

    @Test("No subactions when array is empty")
    func hasSubactionsEmpty() {
        let item = makeItem(subactions: [])
        #expect(ActionMenuCalculations.hasSubactions(item) == false)
    }

    @Test("No subactions when nil")
    func hasSubactionsNil() {
        let item = makeItem(subactions: nil)
        #expect(ActionMenuCalculations.hasSubactions(item) == false)
    }

    // MARK: - isDestructiveItem

    @Test("Destructive item returns true")
    func destructiveTrue() {
        let item = makeItem(isDestructive: true)
        #expect(ActionMenuCalculations.isDestructiveItem(item) == true)
    }

    @Test("Non-destructive item returns false")
    func destructiveFalse() {
        let item = makeItem(isDestructive: false)
        #expect(ActionMenuCalculations.isDestructiveItem(item) == false)
    }

    // MARK: - resolveMenuAction

    @Test("Item with subactions not expanded returns expand")
    func resolveExpandSubactions() {
        let item = makeItem(id: "menu1", subactions: [makeSubitem()])
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: nil)
        #expect(result == .expand("menu1"))
    }

    @Test("Item with subactions already expanded returns collapse")
    func resolveCollapseSubactions() {
        let item = makeItem(id: "menu1", subactions: [makeSubitem()])
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: "menu1")
        #expect(result == .collapse)
    }

    @Test("Item with subactions but different key expanded returns expand")
    func resolveExpandDifferentKey() {
        let item = makeItem(id: "menu1", subactions: [makeSubitem()])
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: "menu2")
        #expect(result == .expand("menu1"))
    }

    @Test("Action-only item returns executeAction")
    func resolveActionOnly() {
        let item = makeItem(isActionOnly: true)
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: nil)
        #expect(result == .executeAction)
    }

    @Test("Item without subactions returns executeAction")
    func resolveNoSubactions() {
        let item = makeItem(subactions: nil)
        let result = ActionMenuCalculations.resolveMenuAction(item: item, expandedKey: nil)
        #expect(result == .executeAction)
    }
}
