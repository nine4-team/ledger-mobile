import FirebaseFirestore

struct ProjectPreferences: Codable, Identifiable {
    @DocumentID var id: String?
    var accountId: String?
    var userId: String?
    var projectId: String?
    var pinnedBudgetCategoryIds: [String]?
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
