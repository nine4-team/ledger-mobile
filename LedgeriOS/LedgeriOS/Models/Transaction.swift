import FirebaseFirestore

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
    var status: String?
    var purchasedBy: String?
    var reimbursementType: String?
    var notes: String?
    var transactionType: String?
    var isCanceled: Bool?
    var budgetCategoryId: String?
    var hasEmailReceipt: Bool?
    var receiptImages: [AttachmentRef]?
    var otherImages: [AttachmentRef]?
    var transactionImages: [AttachmentRef]?
    var needsReview: Bool?
    var taxRatePct: Double?
    var subtotalCents: Int?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
