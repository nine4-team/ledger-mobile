import FirebaseFirestore

struct Item: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var spaceId: String?
    var name: String = ""
    var notes: String?
    var status: String?
    var source: String?
    var sku: String?
    var transactionId: String?
    var purchasePriceCents: Int?
    var projectPriceCents: Int?
    var marketValueCents: Int?
    var purchasedBy: String?
    var bookmark: Bool?
    var budgetCategoryId: String?
    var images: [AttachmentRef]?
    var createdBy: String?
    var updatedBy: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
