import FirebaseFirestore
import Foundation
import Testing
@testable import LedgeriOS

@Suite("Space review notes")
struct SpaceReviewNoteTests {
    private let spaceId = "space-1"

    @Test("reference snapshots a space photo without item annotations")
    func referenceSnapshot() {
        let image = AttachmentRef(
            url: "https://example.com/room.jpg",
            thumbnailUrlSm: "https://example.com/thumb.jpg",
            isPrimary: true,
            checkmarks: [ImageCheckmark(x: 0.2, y: 0.3, itemId: "item-1")],
            isUploading: true
        )
        let reference = SpaceNoteVisualReference(spaceId: spaceId, image: image)

        #expect(reference.image.url == image.url)
        #expect(reference.image.thumbnailUrlSm == image.thumbnailUrlSm)
        #expect(reference.image.checkmarks == nil)
        #expect(reference.image.isPrimary == nil)
        #expect(reference.image.isUploading == nil)
    }

    @Test("marker coordinates are normalized and finite")
    func markerNormalization() {
        #expect(SpaceNoteMarker(x: -4, y: 3) == SpaceNoteMarker(x: 0, y: 1))
        #expect(SpaceNoteMarker(x: .infinity, y: .nan) == SpaceNoteMarker(x: 0.5, y: 0.5))
    }

    @Test("visual reference round trips through Codable")
    func referenceRoundTrip() throws {
        let reference = SpaceNoteVisualReference(
            spaceId: spaceId,
            image: AttachmentRef(url: "gs://bucket/room.jpg", thumbnailUrlMd: "gs://bucket/room_md.jpg"),
            marker: SpaceNoteMarker(x: 0.25, y: 0.75)
        )

        let decoded = try JSONDecoder().decode(
            SpaceNoteVisualReference.self,
            from: JSONEncoder().encode(reference)
        )
        #expect(decoded == reference)
    }

    @Test("note update attaches and explicitly removes a reference")
    func updateFields() throws {
        let reference = SpaceNoteVisualReference(
            spaceId: spaceId,
            image: AttachmentRef(url: "https://example.com/photo.jpg")
        )
        let attached = try SpaceReviewNoteFields.update(text: "Missing from Ledger", visualReference: reference)
        let removed = try SpaceReviewNoteFields.update(text: "Resolved", visualReference: nil)

        #expect((attached["visualReference"] as? [String: Any])?["spaceId"] as? String == spaceId)
        #expect(removed["visualReference"] is FieldValue)
    }

    @Test("a review note cannot reference another space")
    func spaceValidation() {
        let reference = SpaceNoteVisualReference(
            spaceId: "other-space",
            image: AttachmentRef(url: "https://example.com/photo.jpg")
        )
        #expect(throws: SpaceReviewNoteError.self) {
            try SpaceReviewNoteFields.validate(reference, spaceId: spaceId)
        }
    }

    @Test("photo picker accepts only unique completed images")
    func catalog() {
        let images = [
            AttachmentRef(url: "https://example.com/room.jpg"),
            AttachmentRef(url: "https://example.com/room.jpg"),
            AttachmentRef(url: "offline://pending", isUploading: true),
            AttachmentRef(url: "https://example.com/spec.pdf", kind: .pdf),
            AttachmentRef(url: "gs://bucket/second.jpg"),
        ]

        #expect(SpaceReviewPhotoCatalog.availableImages(images).map(\.url) == [
            "https://example.com/room.jpg",
            "gs://bucket/second.jpg",
        ])
    }
}
