import Foundation

struct VendorDefaults: Codable {
    var vendors: [String] = []
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case vendors
    }
}
