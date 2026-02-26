import FirebaseFirestore

struct Project: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var name: String = ""
    var clientName: String = ""
    var description: String?
    var mainImageUrl: String?
    var isArchived: Bool?
    var budgetSummary: ProjectBudgetSummary?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct ProjectBudgetSummary: Codable, Hashable {
    var totalBudgetCents: Int?
    var categories: [BudgetSummaryCategory]?
}

struct BudgetSummaryCategory: Codable, Hashable {
    var budgetCategoryId: String?
    var budgetCents: Int?
}
