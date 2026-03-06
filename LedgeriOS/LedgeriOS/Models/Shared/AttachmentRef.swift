import Foundation

struct AttachmentRef: Codable, Hashable {
    var url: String
    var kind: AttachmentKind = .image
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
    /// H7: True while bytes are being uploaded to Storage. Written immediately with a
    /// placeholder URL so the Firestore record survives upload failures.
    var isUploading: Bool?
}

enum AttachmentKind: String, Codable {
    case image, pdf, file
}
