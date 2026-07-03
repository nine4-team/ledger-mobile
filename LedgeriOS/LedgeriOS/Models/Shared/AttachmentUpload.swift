import Foundation
import UniformTypeIdentifiers

struct AttachmentUpload: Sendable {
    let data: Data
    let originalFileName: String?
    let contentType: String
    let fileExtension: String
    let storageFileName: String

    init(data: Data, originalFileName: String? = nil, contentType: String = "image/jpeg", fileExtension: String = "jpg") {
        self.data = data
        self.originalFileName = originalFileName
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.storageFileName = "\(UUID().uuidString).\(fileExtension)"
    }

    var displayFileName: String {
        originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? storageFileName
    }

    static func image(data: Data, fileName: String? = nil, contentType: UTType? = nil) -> AttachmentUpload {
        let type = contentType ?? .jpeg
        return AttachmentUpload(
            data: data,
            originalFileName: fileName,
            contentType: type.preferredMIMEType ?? "image/jpeg",
            fileExtension: preferredExtension(for: type, fallbackFileName: fileName)
        )
    }

    static func file(data: Data, fileName: String, contentType: UTType) -> AttachmentUpload {
        AttachmentUpload(
            data: data,
            originalFileName: fileName,
            contentType: contentType.preferredMIMEType ?? "application/octet-stream",
            fileExtension: preferredExtension(for: contentType, fallbackFileName: fileName)
        )
    }

    private static func preferredExtension(for type: UTType, fallbackFileName: String?) -> String {
        if let ext = fallbackFileName.map(URL.init(fileURLWithPath:))?.pathExtension.nilIfEmpty {
            return ext.lowercased()
        }
        return type.preferredFilenameExtension ?? "dat"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
