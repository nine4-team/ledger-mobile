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
    /// The item represented by this mark. Optional so checkmarks created before
    /// item matching was introduced remain visible and editable.
    var itemId: String?
    /// All items represented by this mark. New multi-item marks also retain the
    /// first ID in `itemId` so older app builds can still inspect the marker.
    var itemIds: [String]? = nil

    var linkedItemIds: [String] {
        var seen: Set<String> = []
        return ([itemId].compactMap { $0 } + (itemIds ?? [])).filter { id in
            !id.isEmpty && seen.insert(id).inserted
        }
    }

    func linking(_ ids: [String]) -> ImageCheckmark {
        var copy = self
        var seen: Set<String> = []
        let uniqueIds = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        copy.itemId = uniqueIds.first
        copy.itemIds = uniqueIds.count > 1 ? uniqueIds : nil
        return copy
    }
}

extension AttachmentRef {
    /// Firestore-ready representation used when a containing entity rewrites its
    /// embedded attachment array.
    var firestoreDictionary: [String: Any] {
        var fields: [String: Any] = [
            "url": url,
            "kind": kind.rawValue,
        ]
        if let thumbnailUrlSm { fields["thumbnailUrlSm"] = thumbnailUrlSm }
        if let thumbnailUrlMd { fields["thumbnailUrlMd"] = thumbnailUrlMd }
        if let fileName { fields["fileName"] = fileName }
        if let contentType { fields["contentType"] = contentType }
        if let isPrimary { fields["isPrimary"] = isPrimary }
        if let isUploading { fields["isUploading"] = isUploading }
        if let checkmarks {
            fields["checkmarks"] = checkmarks.map { mark in
                var markFields: [String: Any] = [
                    "id": mark.id,
                    "x": mark.x,
                    "y": mark.y,
                ]
                if let itemId = mark.itemId { markFields["itemId"] = itemId }
                if let itemIds = mark.itemIds, !itemIds.isEmpty { markFields["itemIds"] = itemIds }
                return markFields
            }
        }
        return fields
    }
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
