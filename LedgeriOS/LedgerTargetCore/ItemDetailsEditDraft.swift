import Foundation

/// Form values retain their downloaded baseline so unchanged display fallbacks
/// never become writes. Money, vendor selection and movement have other owners.
public struct ItemDetailsEditDraft: Sendable {
    public let itemId: ItemID
    public let original: DownloadedItemDescriptiveDetails
    public var name: String
    public var sku: String
    public var notes: String
    /// Nil preserves the original raw value, including unknown legacy statuses.
    public var selectedStatus: EditItemDetailsCommand.StatusChange?
    public var bookmark: Bool
    public var marketValueText: String

    public init(itemId: ItemID, original: DownloadedItemDescriptiveDetails) {
        self.itemId = itemId; self.original = original
        name = original.displayName; sku = original.sku ?? ""; notes = original.notes ?? ""
        bookmark = original.isBookmarked ?? false
        marketValueText = Self.marketText(original.marketValue)
    }

    private static func marketText(_ value: Money?) -> String {
        guard let value else { return "" }
        let magnitude = value.minorUnits.magnitude
        return (value.minorUnits < 0 ? "-" : "") + "\(magnitude / 100)." + String(format: "%02llu", magnitude % 100)
    }

    /// Nil means unchanged Save: dismiss without creating an operation.
    public static func bulkStatusPayload(rows: [PhysicalItemPlacement],
        selected: EditItemDetailsCommand.StatusChange?) throws -> EditItemDetailsCommand.Payload? {
        guard let selected else { return nil }
        guard !rows.isEmpty, Set(rows.map(\.itemId)).count == rows.count else {
            throw EditItemDetailsCommand.Failure.invalidSelection
        }
        let status = ItemWorkflowStatus(sourceValue: selected == .clear ? nil : selected.rawValue)
        guard rows.contains(where: { $0.workflowStatus != status }) else { return nil }
        return try .init(items: rows.map { .init(itemId: $0.itemId, expectedRevision: $0.itemRevision) },
            changes: .init(status: selected))
    }

    /// Nil means unchanged Save: dismiss without creating an operation.
    public func payload() throws -> EditItemDetailsCommand.Payload? {
        func change(_ value: String, displayed: String) -> EditItemDetailsCommand.TextChange? {
            guard value != displayed else { return nil }
            return value.isEmpty ? .clear : .set(value)
        }
        let nameChange = change(name, displayed: original.displayName)
        let skuChange = change(sku, displayed: original.sku ?? "")
        let notesChange = change(notes, displayed: original.notes ?? "")
        let statusChange = selectedStatus.flatMap { selection -> EditItemDetailsCommand.StatusChange? in
            let selected = ItemWorkflowStatus(sourceValue: selection == .clear ? nil : selection.rawValue)
            return selected == original.workflowStatus ? nil : selection
        }
        let bookmarkChange: Bool? = bookmark == (original.isBookmarked ?? false) ? nil : bookmark
        var marketChange: EditItemDetailsCommand.MarketValueChange?
        if marketValueText != Self.marketText(original.marketValue) {
            if marketValueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if original.marketValue != nil { marketChange = .clear }
            } else {
                let value = try Money.parseNonnegativeEntry(marketValueText,
                    currency: original.marketValue?.currency ?? CurrencyCode(validating: "USD"))
                if value != original.marketValue { marketChange = .set(value) }
            }
        }
        guard nameChange != nil || skuChange != nil || notesChange != nil || statusChange != nil || bookmarkChange != nil || marketChange != nil else { return nil }
        guard let revision = original.itemRevision else { throw EditItemDetailsCommand.Failure.invalidSelection }
        return try .init(items: [.init(itemId: itemId, expectedRevision: revision)],
            changes: .init(name: nameChange, sku: skuChange, notes: notesChange,
                status: statusChange, bookmark: bookmarkChange, marketValue: marketChange))
    }
}
