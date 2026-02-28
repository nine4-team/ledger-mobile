import FirebaseFirestore

struct SpaceTemplate: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String = ""
    var notes: String?
    var checklists: [Checklist]?
    var isArchived: Bool?
    var order: Int?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
