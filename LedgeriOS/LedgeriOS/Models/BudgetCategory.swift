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

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct BudgetCategoryMetadata: Codable, Hashable {
    var categoryType: BudgetCategoryType?
    var excludeFromOverallBudget: Bool?
}
