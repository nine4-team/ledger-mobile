import FirebaseFirestore

struct Item: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var spaceId: String?
    var name: String?
    var description: String?
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
    var quantity: Int?
    var images: [AttachmentRef]?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    /// Best available display name — prefers `name`, falls back to `description`.
    var displayName: String {
        name ?? description ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, spaceId, name, description, notes, status, source, sku,
             transactionId, purchasePriceCents, projectPriceCents, marketValueCents,
             purchasedBy, bookmark, budgetCategoryId, quantity, images, createdBy, updatedBy
    }
}
