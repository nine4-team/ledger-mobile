import FirebaseFirestore

struct IngestionMeta: Codable, Hashable {
    var emailId: String?
    var subject: String?
    var inbox: String?
    var matchConfidence: Double?
    var matchReason: String?
    var orderNumber: String?
    var linkedIngestionIds: [String]?
}

struct TransactionAudit: Codable, Hashable {
    var resolvedSubtotalCents: Int?
    var itemsSumCents: Int?
    var discountCents: Int?
    var varianceCents: Int?
    var variancePercent: Double?
    var linkedItemsSumCents: Int?
    var returnedItemsSumCents: Int?
    var returnedItemsCount: Int?
    var soldItemsSumCents: Int?
    var soldItemsCount: Int?
    var itemsMissingTaxRateCount: Int?
    var itemsMissingTaxRate: [String]?
    var totalItemCount: Int?
}

struct Discount: Codable, Hashable {
    var amountCents: Int
}

struct Transaction: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var projectId: String?
    var transactionDate: String?
    var amountCents: Int?
    var source: String?
    var isCanonicalInventory: Bool?
    var canonicalKind: String?
    var isCanonicalInventorySale: Bool?
    var inventorySaleDirection: InventorySaleDirection?
    var itemIds: [String]?
    var status: TransactionStatus?
    var purchasedBy: String?
    var purchaseHandling: PurchaseHandling?
    var reimbursementType: String?
    var notes: String?
    var transactionType: TransactionType?
    var budgetCategoryId: String?
    var intendedProjectId: String?
    var intendedBudgetCategoryId: String?
    var inventoryIntentResolvedAt: Date?
    var paymentMethod: String?
    var hasEmailReceipt: Bool?
    var receiptImages: [AttachmentRef]?
    var otherImages: [AttachmentRef]?
    var transactionImages: [AttachmentRef]?
    var isComplete: Bool?
    var audit: TransactionAudit?
    var taxRatePct: Double?
    var subtotalCents: Int?
    var discount: Discount?
    var ingestionSource: String?
    var ingestionStatus: String?
    var ingestionMeta: IngestionMeta?
    var triggerEvent: String?
    var settlementInvoiceId: String?
    var settlementInvoiceLineIds: [String]?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, projectId, transactionDate, amountCents, source,
             isCanonicalInventory, canonicalKind, isCanonicalInventorySale, inventorySaleDirection,
             itemIds, status, purchasedBy, purchaseHandling, reimbursementType, notes,
             budgetCategoryId, intendedProjectId, intendedBudgetCategoryId, inventoryIntentResolvedAt,
             paymentMethod, receiptImages, otherImages, transactionImages,
             isComplete, audit, taxRatePct, subtotalCents, discount,
             ingestionSource, ingestionStatus, ingestionMeta, triggerEvent,
             settlementInvoiceId, settlementInvoiceLineIds,
             createdAt, updatedAt
        case transactionType = "type"
        case hasEmailReceipt = "receiptEmailed"
    }

    var isReturnTransaction: Bool {
        transactionType == .return
    }

    /// Legacy fallback only. Itemized audit behavior is category-driven; use
    /// `needsItemizedAudit(category:)` whenever category context is available.
    var needsItemizedAudit: Bool {
        transactionType == .purchase || transactionType == .return
    }

    /// True when the linked budget category is an item category and therefore
    /// gates item/tax/subtotal completeness. If the category is unavailable,
    /// falls back to the legacy type heuristic for old call sites/read models.
    func needsItemizedAudit(category: BudgetCategory?) -> Bool {
        guard let category else { return needsItemizedAudit }
        return category.isItemsCategory
    }

    /// True for transactions that move items between business inventory and
    /// a project: inventory-labeled Purchases (inventory → project), any Sale
    /// (project → inventory acquisition or legacy canonical), and Returns
    /// whose source is the inventory label. Vendor returns are excluded — they
    /// carry a real RMA receipt.
    ///
    /// The inventory-source signal is the `" Inventory"` suffix, which
    /// `InventoryOperationsService.inventoryLabel(for:)` always appends.
    var isInventoryMovement: Bool {
        if transactionType == .sale { return true }
        if transactionType == .purchase,
           let src = source, src.hasSuffix(" Inventory") {
            return true
        }
        if transactionType == .return,
           let src = source, src.hasSuffix(" Inventory") {
            return true
        }
        return false
    }

    /// Sort/display key: explicit `transactionDate` if set, otherwise a `yyyy-MM-dd`
    /// rendering of `createdAt`. Canonical sale transactions (created programmatically
    /// by inventory operations) never set `transactionDate`, so they fall back to createdAt.
    var effectiveSortDate: String {
        if let d = transactionDate, !d.isEmpty { return d }
        if let c = createdAt {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            return f.string(from: c)
        }
        return ""
    }
}
