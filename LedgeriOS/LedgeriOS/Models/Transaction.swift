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
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, projectId, transactionDate, amountCents, source,
             isCanonicalInventory, canonicalKind, isCanonicalInventorySale, inventorySaleDirection,
             itemIds, status, purchasedBy, reimbursementType, notes, isCanceled,
             budgetCategoryId, receiptImages, otherImages, transactionImages,
             needsReview, taxRatePct, subtotalCents
        case transactionType = "type"
        case hasEmailReceipt = "receiptEmailed"
    }
}
