import FirebaseFirestore

struct VendorDefaults: Codable {
    var vendors: [String] = []

    @ServerTimestamp var updatedAt: Date?
}
