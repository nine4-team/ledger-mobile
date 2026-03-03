import FirebaseFirestore

struct SpaceTemplate: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String = ""
    var notes: String?
    var checklists: [Checklist]?
    var isArchived: Bool?
    var order: Int?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, checklists, isArchived, order
    }
}
