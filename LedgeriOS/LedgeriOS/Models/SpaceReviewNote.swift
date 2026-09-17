import FirebaseFirestore
import Foundation

/// One uploaded photo or a snapshot of an existing space photo.
/// The note owns the red marker; item checkmarks remain owned by the source photo.
struct NoteVisualReference: Codable, Hashable, Identifiable, Sendable {
    var spaceId: String?
    var image: AttachmentRef
    var marker: NoteMarker?

    var id: String { "\(spaceId ?? "upload")|\(image.url)" }

    init(spaceId: String? = nil, image: AttachmentRef, marker: NoteMarker? = nil) {
        self.spaceId = spaceId
        var snapshot = image
        snapshot.checkmarks = nil
        snapshot.isPrimary = nil
        snapshot.isUploading = nil
        self.image = snapshot
        self.marker = marker
    }
}

struct NoteMarker: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }
}

enum SpaceReviewNoteError: LocalizedError {
    case differentSpace

    var errorDescription: String? {
        "Choose a photo from this space."
    }
}

enum NoteFields {
    static func validate(_ reference: NoteVisualReference?, spaceId: String) throws {
        if let reference, reference.spaceId != spaceId {
            throw SpaceReviewNoteError.differentSpace
        }
    }

    static func update(text: String, visualReference: NoteVisualReference?) throws -> [String: Any] {
        var fields: [String: Any] = ["text": text, "updatedAt": Date()]
        if let visualReference {
            fields["visualReference"] = try Firestore.Encoder().encode(visualReference)
        } else {
            fields["visualReference"] = FieldValue.delete()
        }
        return fields
    }
}

enum NotePhotoCatalog {
    static func availableImages(_ images: [AttachmentRef]) -> [AttachmentRef] {
        var seen: Set<String> = []
        return images.filter { image in
            image.kind == .image &&
            image.isUploading != true &&
            !image.url.isEmpty &&
            ["https", "http", "gs"].contains(URL(string: image.url)?.scheme?.lowercased() ?? "") &&
            seen.insert(image.url).inserted
        }
    }
}

// Backward-compatible names for consumers of the original space-note API.
typealias SpaceNoteVisualReference = NoteVisualReference
typealias SpaceNoteMarker = NoteMarker
typealias SpaceReviewNoteFields = NoteFields
typealias SpaceReviewPhotoCatalog = NotePhotoCatalog

enum NoteScope: Hashable {
    case project(String)
    case space(String)

    var spaceId: String? {
        if case .space(let id) = self { return id }
        return nil
    }

    func collectionPath(accountId: String) -> String {
        switch self {
        case .project(let id): return "accounts/\(accountId)/projects/\(id)/notes"
        case .space(let id): return "accounts/\(accountId)/spaces/\(id)/reviewNotes"
        }
    }
}
