import FirebaseFirestore

struct TransactionAudit: Codable, Hashable {
    var resolvedSubtotalCents: Int?
    var itemsSumCents: Int?
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
    var reimbursementType: String?
    var notes: String?
    var transactionType: TransactionType?
    var budgetCategoryId: String?
    var paymentMethod: String?
    var hasEmailReceipt: Bool?
    var receiptImages: [AttachmentRef]?
    var otherImages: [AttachmentRef]?
    var transactionImages: [AttachmentRef]?
    var needsReview: Bool?
    var isComplete: Bool?
    var audit: TransactionAudit?
    var taxRatePct: Double?
    var subtotalCents: Int?
    var triggerEvent: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, projectId, transactionDate, amountCents, source,
             isCanonicalInventory, canonicalKind, isCanonicalInventorySale, inventorySaleDirection,
             itemIds, status, purchasedBy, reimbursementType, notes,
             budgetCategoryId, paymentMethod, receiptImages, otherImages, transactionImages,
             needsReview, isComplete, audit, taxRatePct, subtotalCents, triggerEvent
        case transactionType = "type"
        case hasEmailReceipt = "receiptEmailed"
    }

    var isReturnTransaction: Bool {
        transactionType == .return || canonicalKind == "return"
    }
}
