import FirebaseFirestore

struct Space: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var projectId: String?
    var name: String = ""
    var notes: String?
    var images: [AttachmentRef]?
    var checklists: [Checklist]?
    var isArchived: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, projectId, name, notes, images, checklists, isArchived
    }
}

struct Checklist: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String = ""
    var items: [ChecklistItem] = []
}

struct ChecklistItem: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var text: String = ""
    var isChecked: Bool = false
}
