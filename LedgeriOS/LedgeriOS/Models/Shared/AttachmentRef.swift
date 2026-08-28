import Foundation

struct AttachmentRef: Codable, Hashable, Sendable {
    var url: String
    var thumbnailUrlSm: String?
    var thumbnailUrlMd: String?
    var kind: AttachmentKind = .image
    var fileName: String?
    var contentType: String?
    var isPrimary: Bool?
    /// Non-destructive visual checkmarks positioned over this attachment. Coordinates
    /// are normalized to the image bounds so the marks work at every display size.
    var checkmarks: [ImageCheckmark]?
    /// H7: True while bytes are being uploaded to Storage. Written immediately with a
    /// placeholder URL so the Firestore record survives upload failures.
    var isUploading: Bool?
}

struct ImageCheckmark: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var x: Double
    var y: Double
}

enum AttachmentKind: String, Codable, Sendable {
    case image, pdf, file
}

/// Enforces the attachment invariant used by items, transactions, spaces, and
/// quick drafts: every non-empty attachment collection has exactly one primary.
enum AttachmentPrimaryPolicy {
    static func normalized(_ item: Item) -> Item {
        var normalizedItem = item
        if let images = item.images {
            normalizedItem.images = normalized(images)
        }
        return normalizedItem
    }

    static func normalized(_ attachments: [AttachmentRef]) -> [AttachmentRef] {
        guard !attachments.isEmpty else { return [] }
        let primaryIndex = attachments.firstIndex { $0.isPrimary == true } ?? attachments.startIndex

        return attachments.enumerated().map { index, attachment in
            var normalized = attachment
            normalized.isPrimary = index == primaryIndex
            return normalized
        }
    }

    /// Normalizes Firestore-ready attachment dictionaries without discarding
    /// fields that are unknown to the current app version.
    static func normalizedDictionaries(_ attachments: [[String: Any]]) -> [[String: Any]] {
        guard !attachments.isEmpty else { return [] }
        let primaryIndex = attachments.firstIndex { $0["isPrimary"] as? Bool == true }
            ?? attachments.startIndex

        return attachments.enumerated().map { index, attachment in
            var normalized = attachment
            normalized["isPrimary"] = index == primaryIndex
            return normalized
        }
    }

    static func normalizedFields(
        _ fields: [String: Any],
        attachmentFieldNames: Set<String>
    ) -> [String: Any] {
        var normalized = fields
        for fieldName in attachmentFieldNames {
            if let attachments = fields[fieldName] as? [[String: Any]] {
                normalized[fieldName] = normalizedDictionaries(attachments)
            }
        }
        return normalized
    }
}
