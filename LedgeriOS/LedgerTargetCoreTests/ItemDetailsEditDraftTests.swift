import Testing
@testable import LedgerTargetCore

struct ItemDetailsEditDraftTests {
    @Test func marketDraftDistinguishesClearZeroNoOpAndInvalid() throws {
        let usd = try CurrencyCode(validating: "USD")
        var draft = ItemDetailsEditDraft(itemId: try .init(validating: "item"),
            original: .init(description: "Chair", itemRevision: 3,
                marketValue: Money(minorUnits: 1250, currency: usd)))
        #expect(draft.marketValueText == "12.50")
        draft.marketValueText = "12.5"
        #expect(try draft.payload() == nil)
        draft.marketValueText = "0"
        #expect(try draft.payload()?.changes.marketValue == .set(Money(minorUnits: 0, currency: usd)))
        draft.marketValueText = ""
        #expect(try draft.payload()?.changes.marketValue == .clear)
        draft.marketValueText = "oops"
        #expect(throws: (any Error).self) { try draft.payload() }
        let legacy = ItemDetailsEditDraft(itemId: try .init(validating: "legacy"),
            original: .init(description: "Legacy", itemRevision: 1,
                marketValue: Money(minorUnits: -1, currency: usd)))
        #expect(legacy.marketValueText == "-0.01")
        #expect(try legacy.payload() == nil)
    }

    @Test func bulkStatusKeepsWholeSelectionAndRevisionsAndSkipsNoOp() throws {
        let first = try PhysicalItemPlacement(itemId: .init(validating: "one"), description: "Chair",
            itemRevision: 3, placementId: .init(validating: "p-one"), scope: .businessInventory,
            spaceId: nil, workflowStatusRaw: "to-purchase")
        let second = try PhysicalItemPlacement(itemId: .init(validating: "two"), description: "Table",
            itemRevision: 7, placementId: .init(validating: "p-two"), scope: .businessInventory,
            spaceId: nil, workflowStatusRaw: "legacy")
        #expect(try ItemDetailsEditDraft.bulkStatusPayload(rows: [first, second], selected: nil) == nil)
        #expect(try ItemDetailsEditDraft.bulkStatusPayload(rows: [first], selected: .toPurchase) == nil)
        let payload = try #require(try ItemDetailsEditDraft.bulkStatusPayload(rows: [first, second], selected: .toPurchase))
        #expect(payload.items.map(\.expectedRevision) == [3, 7])
        #expect(payload.items.map(\.itemId) == [first.itemId, second.itemId])
        #expect(payload.changes == .init(status: .toPurchase))
        #expect(try ItemDetailsEditDraft.bulkStatusPayload(rows: [second], selected: .clear)?.changes.status == .clear)
        #expect(throws: EditItemDetailsCommand.Failure.invalidSelection) {
            try ItemDetailsEditDraft.bulkStatusPayload(rows: [first, first], selected: .returned)
        }
    }

    @Test func statusSelectionPreservesAliasesAndUnknownEvidenceUntilChanged() throws {
        var draft = ItemDetailsEditDraft(itemId: try .init(validating: "item"),
            original: .init(description: "Chair", workflowStatusRaw: "to-purchase", itemRevision: 3))
        draft.selectedStatus = .toPurchase
        #expect(try draft.payload() == nil)
        draft.selectedStatus = .returned
        #expect(try draft.payload()?.changes.status == .returned)
        draft.selectedStatus = .clear
        #expect(try draft.payload()?.changes.status == .clear)
        var unknown = ItemDetailsEditDraft(itemId: try .init(validating: "item"),
            original: .init(description: "Chair", workflowStatusRaw: "legacy", itemRevision: 3))
        #expect(try unknown.payload() == nil)
        unknown.selectedStatus = .clear
        #expect(try unknown.payload()?.changes.status == .clear)
    }

    @Test func bookmarkToggleIsAnExplicitChangeOnly() throws {
        var draft = ItemDetailsEditDraft(itemId: try .init(validating: "item"),
            original: .init(description: "Chair", itemRevision: 3))
        #expect(try draft.payload() == nil)
        draft.bookmark = true
        #expect(try draft.payload()?.changes.bookmark == true)
        #expect(try draft.payload()?.changes.status == nil)
        draft.bookmark = false
        #expect(try draft.payload() == nil)
    }

    @Test func unchangedFallbackAndUnknownFieldsRemainUntouched() throws {
        var draft = ItemDetailsEditDraft(itemId: try .init(validating: "item"),
            original: .init(description: "Legacy chair", sku: "SKU", notes: "  original\nnotes  ",
                workflowStatusRaw: "legacy-unknown", itemRevision: 8))
        #expect(try draft.payload() == nil)
        draft.sku = ""
        let payload = try #require(try draft.payload())
        #expect(payload.items[0].expectedRevision == 8)
        #expect(payload.changes.sku == .clear)
        #expect(payload.changes.name == nil)
        #expect(payload.changes.notes == nil)
        #expect(payload.changes.status == nil)
        #expect(payload.changes.bookmark == nil)
        draft.name = "New chair"
        draft.notes = "  new\nnotes  "
        #expect(try draft.payload()?.changes.name == .set("New chair"))
        #expect(try draft.payload()?.changes.notes == .set("  new\nnotes  "))
    }

    @Test func missingRevisionCannotWriteAndCancelNeedsNoCommand() throws {
        var draft = ItemDetailsEditDraft(itemId: try .init(validating: "item"), original: .init(description: "Legacy"))
        #expect(try draft.payload() == nil)
        draft.name = "Changed"
        #expect(throws: EditItemDetailsCommand.Failure.invalidSelection) { try draft.payload() }
        draft.name = "Legacy"
        #expect(try draft.payload() == nil)
    }
}
