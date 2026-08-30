import SwiftUI

private extension SpaceNoteVisualReference {
    var annotations: [ZoomableImageAnnotation] {
        guard let marker else { return [] }
        return [ZoomableImageAnnotation(
            id: "space-review-note-marker",
            point: CGPoint(x: marker.x, y: marker.y),
            accessibilityLabel: "Review note marker",
            style: .noteReference
        )]
    }
}

struct SpaceNoteReferenceThumbnail: View {
    let reference: SpaceNoteVisualReference
    var height: CGFloat = 140

    var body: some View {
        FirebaseImage(
            url: reference.image.url,
            thumbnailUrl: reference.image.thumbnailUrlMd ?? reference.image.thumbnailUrlSm,
            contentMode: .fit,
            annotations: reference.annotations
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        }
        .accessibilityLabel(reference.marker == nil
            ? "Space photo attached to this review note"
            : "Space photo with a red review note marker")
    }
}

struct SpaceNoteVisualReferenceField: View {
    let spaceId: String
    let photos: [AttachmentRef]
    @Binding var reference: SpaceNoteVisualReference?

    @State private var showPhotoPicker = false
    @State private var showMarkerEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let reference {
                Button { showMarkerEditor = true } label: {
                    SpaceNoteReferenceThumbnail(reference: reference, height: 170)
                }
                .buttonStyle(.plain)

                HStack(spacing: Spacing.md) {
                    Button(reference.marker == nil ? "Mark item" : "Move mark") {
                        showMarkerEditor = true
                    }
                    Button("Change photo") { showPhotoPicker = true }
                    Spacer(minLength: 0)
                    Button("Remove", role: .destructive) { self.reference = nil }
                }
                .font(Typography.small)
                .controlSize(.small)
            } else {
                Button { showPhotoPicker = true } label: {
                    Label("Choose a space photo", systemImage: "photo.badge.plus")
                }
                Text("Optional. Add a red mark if the note refers to something specific in the photo.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .adaptivePresentation(isPresented: $showPhotoPicker, style: .fullSheet) {
            SpaceReviewPhotoPicker(spaceId: spaceId, photos: photos) { selected in
                reference = SpaceNoteVisualReference(spaceId: spaceId, image: selected)
            }
        }
        .adaptivePresentation(isPresented: $showMarkerEditor, style: .viewer) {
            if let reference {
                SpaceNoteReferenceViewer(reference: reference, isEditing: true) { marker in
                    self.reference?.marker = marker
                }
            }
        }
    }
}

struct SpaceNoteReferenceViewer: View {
    let reference: SpaceNoteVisualReference
    var noteText: String?
    let isEditing: Bool
    var onSave: ((SpaceNoteMarker?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var marker: SpaceNoteMarker?
    @State private var zoomScale: CGFloat = 1

    init(
        reference: SpaceNoteVisualReference,
        noteText: String? = nil,
        isEditing: Bool = false,
        onSave: ((SpaceNoteMarker?) -> Void)? = nil
    ) {
        self.reference = reference
        self.noteText = noteText
        self.isEditing = isEditing
        self.onSave = onSave
        _marker = State(initialValue: reference.marker)
    }

    private var draftAnnotations: [ZoomableImageAnnotation] {
        guard let marker else { return [] }
        return [ZoomableImageAnnotation(
            id: "space-review-note-marker",
            point: CGPoint(x: marker.x, y: marker.y),
            accessibilityLabel: "Review note marker",
            style: .noteReference
        )]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZoomableScrollView(
                    url: URL(string: reference.image.url),
                    zoomScale: $zoomScale,
                    annotations: draftAnnotations,
                    annotationSelectionEnabled: false,
                    onImageTap: isEditing ? { point in
                        marker = SpaceNoteMarker(x: point.x, y: point.y)
                    } : nil
                )
                .background(Color.black)
                .accessibilityLabel("Space review reference photo")
                .accessibilityAction(named: "Place mark at center") {
                    if isEditing { marker = SpaceNoteMarker(x: 0.5, y: 0.5) }
                }

                controls
            }
            .navigationTitle(isEditing ? "Mark what you mean" : "Review note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Close") { dismiss() }
                }
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onSave?(marker)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isEditing {
                Text(marker == nil
                     ? "Tap the item this note refers to, or finish without a mark."
                     : "Tap elsewhere to move the red mark.")
                    .font(Typography.small)
            } else if let noteText, !noteText.isEmpty {
                ScrollView {
                    SelectableNoteText(text: noteText, style: .body)
                }
                .frame(maxHeight: 100)
            }

            HStack {
                Button { zoomScale = max(1, zoomScale / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel("Zoom out")
                Button { zoomScale = min(5, zoomScale * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel("Zoom in")
                Spacer()
                if isEditing, marker != nil {
                    Button("Remove mark", role: .destructive) { marker = nil }
                }
            }

            if isEditing, marker != nil {
                DisclosureGroup("Position controls") {
                    Slider(value: coordinate(\.x), in: 0...1) { Text("Horizontal position") }
                    Slider(value: coordinate(\.y), in: 0...1) { Text("Vertical position") }
                }
                .font(Typography.caption)
            }
        }
        .padding(Spacing.md)
        .background(.bar)
    }

    private func coordinate(_ keyPath: WritableKeyPath<SpaceNoteMarker, Double>) -> Binding<Double> {
        Binding(
            get: { marker?[keyPath: keyPath] ?? 0.5 },
            set: { marker?[keyPath: keyPath] = $0 }
        )
    }
}

private struct SpaceReviewPhotoPicker: View {
    let spaceId: String
    let photos: [AttachmentRef]
    let onSelect: (AttachmentRef) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availablePhotos: [AttachmentRef] {
        SpaceReviewPhotoCatalog.availableImages(photos)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No space photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Add a photo to this space first, then attach it to a review note.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 145), spacing: Spacing.sm)],
                            spacing: Spacing.sm
                        ) {
                            ForEach(Array(availablePhotos.enumerated()), id: \.element.url) { index, photo in
                                Button {
                                    onSelect(photo)
                                    dismiss()
                                } label: {
                                    FirebaseImage(
                                        url: photo.url,
                                        thumbnailUrl: photo.thumbnailUrlSm ?? photo.thumbnailUrlMd,
                                        contentMode: .fit
                                    )
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                                    .background(BrandColors.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Choose space photo \(index + 1)")
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .background(BrandColors.background)
            .navigationTitle("Choose space photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct SpaceReviewNoteEditor: View {
    let spaceId: String
    let photos: [AttachmentRef]
    let isEditing: Bool
    let onSave: (String, SpaceNoteVisualReference?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var reference: SpaceNoteVisualReference?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        spaceId: String,
        photos: [AttachmentRef],
        note: SpaceReviewNote? = nil,
        initialPhoto: AttachmentRef? = nil,
        onSave: @escaping (String, SpaceNoteVisualReference?) async throws -> Void
    ) {
        self.spaceId = spaceId
        self.photos = photos
        self.isEditing = note != nil
        self.onSave = onSave
        _text = State(initialValue: note?.text ?? "")
        _reference = State(initialValue: note?.visualReference ?? initialPhoto.map {
            SpaceNoteVisualReference(spaceId: spaceId, image: $0)
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("What needs attention?")
                            .font(Typography.label)
                        TextField("Describe what is missing, unclear, or not represented in Ledger", text: $text, axis: .vertical)
                            .lineLimit(4...12)
                            .formInputStyle()
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Visual reference")
                            .font(Typography.label)
                        SpaceNoteVisualReferenceField(
                            spaceId: spaceId,
                            photos: photos,
                            reference: $reference
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typography.small)
                            .foregroundStyle(.red)
                    }
                }
                .padding(Spacing.screenPadding)
                .disabled(isSaving)
            }
            .navigationTitle(isEditing ? "Edit review note" : "Add review note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || trimmedText.isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedText.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await onSave(trimmedText, reference)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
