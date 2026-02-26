import FirebaseFirestore

struct AccountMember: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var accountId: String?
    var uid: String?
    var role: MemberRole?
    var email: String?
    var name: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
