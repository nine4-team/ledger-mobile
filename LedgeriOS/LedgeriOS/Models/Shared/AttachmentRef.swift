import Foundation

struct AttachmentRef: Codable, Hashable, Sendable {
    var url: String
    var thumbnailUrlSm: String?
    var thumbnailUrlMd: String?
    var kind: AttachmentKind = .image
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
    /// H7: True while bytes are being uploaded to Storage. Written immediately with a
    /// placeholder URL so the Firestore record survives upload failures.
    var isUploading: Bool?
}

enum AttachmentKind: String, Codable, Sendable {
    case image, pdf, file
}
