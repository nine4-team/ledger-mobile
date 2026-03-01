import FirebaseFirestore

struct AccountMember: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var accountId: String?
    var uid: String?
    var role: MemberRole?
    var email: String?
    var name: String?
    var createdAt: Date?
    var updatedAt: Date?

    // Exclude timestamps from decoding — emulator data stores these as ISO strings
    // but Firestore Codable expects native Timestamp objects. The fields aren't
    // needed for discovery or current UI. Can add a flexible decoder later.
    enum CodingKeys: String, CodingKey {
        case id, accountId, uid, role, email, name
    }
}
