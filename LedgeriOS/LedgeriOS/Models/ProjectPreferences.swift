import FirebaseFirestore

struct ProjectPreferences: Codable, Identifiable {
    @DocumentID var id: String?
    var accountId: String?
    var userId: String?
    var projectId: String?
    var pinnedBudgetCategoryIds: [String]?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, userId, projectId, pinnedBudgetCategoryIds
    }
}
