import FirebaseFirestore

struct Project: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var name: String = ""
    var clientName: String = ""
    var description: String?
    var mainImageUrl: String?
    var mainImageThumbUrlSm: String?
    var mainImageThumbUrlMd: String?
    var isArchived: Bool?
    var paymentMethodLast4: String?
    var budgetSummary: ProjectBudgetSummary?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, name, clientName, description, mainImageUrl, mainImageThumbUrlSm, mainImageThumbUrlMd, isArchived, paymentMethodLast4, budgetSummary
    }
}

struct ProjectBudgetSummary: Codable, Hashable {
    var totalBudgetCents: Int?
    var spentCents: Int?
    var categories: [String: BudgetSummaryCategory]?
}

struct BudgetSummaryCategory: Codable, Hashable {
    var budgetCents: Int?
    var spentCents: Int?
    var name: String?
    var categoryType: String?
    var isArchived: Bool?
    var excludeFromOverallBudget: Bool?
}
