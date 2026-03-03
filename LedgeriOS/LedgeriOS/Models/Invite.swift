import FirebaseFirestore

struct Invite: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var email: String = ""
    var role: String = ""
    var token: String?
    var createdByUid: String?
    var createdAt: Date?
    var acceptedAt: Date?
    var revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, email, role, token, createdByUid, acceptedAt, revokedAt
    }
}
