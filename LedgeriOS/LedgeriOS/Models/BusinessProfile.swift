import FirebaseFirestore

struct BusinessProfile: Codable {
    var name: String?
    var logoUrl: String?

    @ServerTimestamp var updatedAt: Date?
}
