import FirebaseFirestore

struct ProjectBudgetCategory: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var budgetCents: Int?
    var createdBy: String?
    var updatedBy: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
