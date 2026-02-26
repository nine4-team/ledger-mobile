import Foundation

struct AttachmentRef: Codable, Hashable {
    var url: String
    var kind: AttachmentKind = .image
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
}

enum AttachmentKind: String, Codable {
    case image, pdf, file
}
