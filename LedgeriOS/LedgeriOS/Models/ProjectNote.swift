import FirebaseFirestore

struct ProjectNote: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var text: String = ""
    var createdBy: String = ""
    var createdByName: String = ""
    var source: String = "text"
    var createdAt: Date?
}
