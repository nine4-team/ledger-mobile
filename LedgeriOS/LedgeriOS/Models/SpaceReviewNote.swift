import FirebaseFirestore
import Foundation

/// An observation made while reconciling a physical space with Ledger.
/// This is intentionally separate from project notes and the space's legacy free-text notes.
struct SpaceReviewNote: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var text: String = ""
    var createdBy: String = ""
    var createdByName: String = ""
    var createdAt: Date?
    var updatedAt: Date?
    var visualReference: SpaceNoteVisualReference?
}

/// A lightweight snapshot of one photo already attached to the note's space.
/// The note owns the red marker; item checkmarks remain owned by the source photo.
struct SpaceNoteVisualReference: Codable, Hashable, Identifiable, Sendable {
    var spaceId: String
    var image: AttachmentRef
    var marker: SpaceNoteMarker?

    var id: String { "\(spaceId)|\(image.url)" }

    init(spaceId: String, image: AttachmentRef, marker: SpaceNoteMarker? = nil) {
        self.spaceId = spaceId
        var snapshot = image
        snapshot.checkmarks = nil
        snapshot.isPrimary = nil
        snapshot.isUploading = nil
        self.image = snapshot
        self.marker = marker
    }
}

struct SpaceNoteMarker: Codable, Hashable, Sendable {
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

enum SpaceReviewNoteFields {
    static func validate(_ reference: SpaceNoteVisualReference?, spaceId: String) throws {
        if let reference, reference.spaceId != spaceId {
            throw SpaceReviewNoteError.differentSpace
        }
    }

    static func update(text: String, visualReference: SpaceNoteVisualReference?) throws -> [String: Any] {
        var fields: [String: Any] = ["text": text, "updatedAt": Date()]
        if let visualReference {
            fields["visualReference"] = try Firestore.Encoder().encode(visualReference)
        } else {
            fields["visualReference"] = FieldValue.delete()
        }
        return fields
    }
}

enum SpaceReviewPhotoCatalog {
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
