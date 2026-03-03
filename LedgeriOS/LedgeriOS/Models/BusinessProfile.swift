import Foundation

struct BusinessProfile: Codable {
    var name: String?
    var logoUrl: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, logoUrl
    }
}
