import FirebaseFirestore

struct BudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var slug: String?
    var isArchived: Bool?
    var order: Int?
    var metadata: BudgetCategoryMetadata?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, name, slug, isArchived, order, metadata
    }
}

struct BudgetCategoryMetadata: Codable, Hashable {
    var categoryType: BudgetCategoryType?
    var excludeFromOverallBudget: Bool?
}
