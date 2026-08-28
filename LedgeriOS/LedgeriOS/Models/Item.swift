import FirebaseFirestore

struct Item: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var spaceId: String?
    var name: String?
    var description: String?
    var notes: String?
    var status: ItemStatus?

    /// **Original vendor** — where the item was first acquired (e.g. "Homegoods",
    /// "Wayfair"). Free-form string set once at item creation and **never
    /// overwritten** by scope moves (sell-to-project, return-to-inventory,
    /// project-to-project sales). Used for: routing returns back to the original
    /// store, grouping items by vendor, the editable "Source" field in the item
    /// detail modal, and picker filters that match items to a transaction's
    /// vendor. **Not what you want on a search card** — use `currentSource` for
    /// "where it came from right now".
    var source: String?

    /// **Immediate/current source** — where the item came from on its most recent
    /// scope move. Mutable: denormalized from the item's current transaction
    /// `source` so search cards can render the immediate origin without a
    /// per-row transaction lookup.
    ///
    /// Update rules (all written by `InventoryOperationsService`):
    /// - `sellToProject`: set to the inventory label (e.g. "Business Inventory"
    ///   or "1584 Design Inventory") — items sold from inventory are "from
    ///   Inventory" from the project's perspective.
    /// - `returnToInventory`: set to the inventory label (items returning home).
    /// - `sellItemsFromProjectToProject`: set to the inventory label (the sale is
    ///   modeled internally as two hops via inventory).
    /// - `reassignToProject` / `returnToTransaction`: **not touched** (within-
    ///   project moves don't change the immediate source).
    ///
    /// At creation time, callers set `currentSource = source` because the
    /// immediate source IS the original vendor on day one.
    ///
    /// Legacy items pre-dating this field have `currentSource == nil`; display
    /// callers should fall back to `source`.
    var currentSource: String?

    var sku: String?
    var transactionId: String?
    var purchasePriceCents: Int?
    var projectPriceCents: Int?
    var marketValueCents: Int?
    var purchasedBy: String?
    var bookmark: Bool?
    var budgetCategoryId: String?
    var quantity: Int?
    var taxRatePct: Double?
    var taxAmountPurchasePriceCents: Int?
    var taxAmountProjectPriceCents: Int?

    /// Immutable accounting snapshot captured when the item most recently
    /// entered business inventory from a project. Return-to-project uses this
    /// instead of mutable item pricing so it can reverse the original project
    /// movement into the same project/category for the same amount.
    var inventoryEntryTransactionId: String?
    var inventoryEntryProjectId: String?
    var inventoryEntryBudgetCategoryId: String?
    var inventoryEntryPriceCents: Int?
    var inventoryEntryAmountCents: Int?
    var images: [AttachmentRef]?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    /// Best available display name — prefers `name`, falls back to `description`.
    var displayName: String {
        name ?? description ?? ""
    }

    /// Current client-facing price with the purchase-cost floor applied.
    /// This is also used defensively for legacy documents that have not yet
    /// been repaired in Firestore.
    var normalizedProjectPriceCents: Int? {
        ItemPricePolicy.normalizedProjectPriceCents(
            purchasePriceCents: purchasePriceCents,
            projectPriceCents: projectPriceCents
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, spaceId, name, description, notes, status,
             source, currentSource, sku,
             transactionId, purchasePriceCents, projectPriceCents, marketValueCents,
             purchasedBy, bookmark, budgetCategoryId, quantity,
             taxRatePct, taxAmountPurchasePriceCents, taxAmountProjectPriceCents,
             inventoryEntryTransactionId, inventoryEntryProjectId,
             inventoryEntryBudgetCategoryId, inventoryEntryPriceCents,
             inventoryEntryAmountCents,
             images, createdBy, updatedBy, createdAt, updatedAt
    }
}

enum ItemPricePolicy {
    static func normalizedProjectPriceCents(
        purchasePriceCents: Int?,
        projectPriceCents: Int?
    ) -> Int? {
        guard purchasePriceCents != nil || projectPriceCents != nil else { return nil }
        return max(purchasePriceCents ?? 0, projectPriceCents ?? 0)
    }

    static func normalizedForPersistence(_ item: Item) -> Item {
        var normalized = item
        normalized.projectPriceCents = normalizedProjectPriceCents(
            purchasePriceCents: item.purchasePriceCents,
            projectPriceCents: item.projectPriceCents
        )
        return normalized
    }

    /// Applies the floor to the merged post-update state. This prevents a
    /// partial update from bypassing the invariant by omitting the other price.
    static func normalizedUpdateFields(
        existing: Item,
        fields: [String: Any]
    ) -> [String: Any] {
        var normalizedFields = fields
        let purchasePrice = mergedPrice(
            key: "purchasePriceCents",
            existing: existing.purchasePriceCents,
            fields: fields
        )
        let projectPrice = mergedPrice(
            key: "projectPriceCents",
            existing: existing.projectPriceCents,
            fields: fields
        )

        if let normalizedProjectPrice = normalizedProjectPriceCents(
            purchasePriceCents: purchasePrice,
            projectPriceCents: projectPrice
        ) {
            normalizedFields["projectPriceCents"] = normalizedProjectPrice
        }
        return normalizedFields
    }

    private static func mergedPrice(
        key: String,
        existing: Int?,
        fields: [String: Any]
    ) -> Int? {
        guard let incoming = fields[key] else { return existing }
        if incoming is NSNull { return nil }
        if let value = incoming as? Int { return value }
        if let value = incoming as? NSNumber { return value.intValue }
        return existing
    }
}
