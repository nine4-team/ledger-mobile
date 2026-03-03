import FirebaseFirestore

struct ProjectBudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var budgetCents: Int?
    var createdBy: String?
    var updatedBy: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, budgetCents, createdBy, updatedBy
    }
}
