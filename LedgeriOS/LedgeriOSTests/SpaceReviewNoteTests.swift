import FirebaseFirestore
import Foundation
import Testing
@testable import LedgeriOS

@Suite("Space review notes")
struct SpaceReviewNoteTests {
    @Test("Existing project and space notes decode into one shared model")
    func legacyNotesDecode() throws {
        let base: [String: Any] = ["text": "Existing note", "createdBy": "user", "createdByName": "Designer"]
        let space = try Firestore.Decoder().decode(LedgerNote.self, from: base, in: Firestore.firestore().document("testNotes/legacy-space"))
        var projectFields = base
        projectFields["source"] = "text"
        let project = try Firestore.Decoder().decode(LedgerNote.self, from: projectFields, in: Firestore.firestore().document("testNotes/legacy-project"))
        #expect(space.text == project.text)
        #expect(space.visualReference == nil)
        #expect(project.visualReference == nil)
        #expect(project.source == "text")
    }

    @Test("Project uploads preserve their image and marker without requiring a space")
    func projectPhotoRoundTrip() throws {
        var note = LedgerNote()
        note.text = "Move this item"
        note.visualReference = NoteVisualReference(
            image: AttachmentRef(url: "https://example.com/upload.jpg"),
            marker: NoteMarker(x: 0.3, y: 0.7)
        )
        let encoded = try Firestore.Encoder().encode(note)
        let decoded = try Firestore.Decoder().decode(LedgerNote.self, from: encoded, in: Firestore.firestore().document("testNotes/photo"))
        #expect(decoded.visualReference == note.visualReference)
        #expect(decoded.visualReference?.spaceId == nil)
    }

    @Test("Existing note collections retain their storage paths")
    func scopePaths() {
        #expect(NoteScope.project("p").collectionPath(accountId: "a") == "accounts/a/projects/p/notes")
        #expect(NoteScope.space("s").collectionPath(accountId: "a") == "accounts/a/spaces/s/reviewNotes")
    }

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

#if canImport(UIKit)
import UIKit
import SwiftUI

@Suite("Note photo viewer layout")
@MainActor
struct NotePhotoViewerLayoutTests {
    @Test("A cached photo loaded before layout fits once bounds become available")
    func cachedPhotoBeforeLayout() throws {
        let url = try #require(URL(string: "https://example.com/note-layout-test.jpg"))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        ImageCache.store(image, for: url.absoluteString, cost: 0)
        let viewer = ZoomableScrollView(url: url, zoomScale: .constant(1))
        let coordinator = viewer.makeCoordinator()
        let scrollView = UIScrollView()
        scrollView.delegate = coordinator
        let imageView = UIImageView()
        scrollView.addSubview(imageView)
        coordinator.imageView = imageView
        coordinator.loadImage(url: url)
        #expect(imageView.image != nil)

        scrollView.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        coordinator.layoutImage()
        #expect(abs(scrollView.minimumZoomScale - 0.25) < 0.001)
        #expect(abs(scrollView.zoomScale - 0.25) < 0.001)
        #expect(abs(imageView.frame.width - 300) < 0.1)

        // Ordinary layouts preserve user zoom; rotation refits the photo.
        scrollView.zoomScale = 0.5
        coordinator.layoutImage()
        #expect(abs(scrollView.zoomScale - 0.5) < 0.001)
        scrollView.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        coordinator.layoutImage()
        #expect(abs(scrollView.zoomScale - 0.375) < 0.001)
    }
}
#endif
