import FirebaseFirestore

struct Account: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var name: String = ""
    var ownerUid: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, ownerUid
    }
}
