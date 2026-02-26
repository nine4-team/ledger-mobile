import FirebaseFirestore

struct Account: Codable, Identifiable, Hashable, @unchecked Sendable {
    @DocumentID var id: String?
    var name: String = ""
    var ownerUid: String?

    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}
