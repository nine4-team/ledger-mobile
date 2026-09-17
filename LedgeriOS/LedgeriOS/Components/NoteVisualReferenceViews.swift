import SwiftUI
import PhotosUI

private extension NoteVisualReference {
    var annotations: [ZoomableImageAnnotation] {
        guard let marker else { return [] }
        return [ZoomableImageAnnotation(
            id: "note-marker",
            point: CGPoint(x: marker.x, y: marker.y),
            accessibilityLabel: "Note marker",
            style: .noteReference
        )]
    }
}

struct NoteReferenceThumbnail: View {
    let reference: NoteVisualReference
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
            ? "Photo attached to this note"
            : "Photo with a red note marker")
    }
}

struct NoteVisualReferenceField: View {
    let scope: NoteScope?
    let photos: [AttachmentRef]
    @Binding var reference: NoteVisualReference?
    @Binding var isProcessing: Bool
    @Binding var newUploads: [AttachmentRef]
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var uploadError: String?

    @State private var showPhotoPicker = false
    @State private var showMarkerEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("Photo library", systemImage: "photo")
                }
                #if os(iOS)
                Button { showCamera = true } label: {
                    Label("Take photo", systemImage: "camera")
                }
                #endif
            }
            .disabled(isProcessing || scope == nil)
            if isProcessing { ProgressView("Preparing photo…") }
            if let uploadError { Text(uploadError).foregroundStyle(.red).font(Typography.small) }
            if let reference {
                Button { showMarkerEditor = true } label: {
                    NoteReferenceThumbnail(reference: reference, height: 170)
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
                    Label("Choose an existing photo", systemImage: "photo.badge.plus")
                }
                Text("Optional. Add a red mark if the note refers to something specific in the photo.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .disabled(isProcessing)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            isProcessing = true
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try await attach(data)
                } catch { uploadError = error.localizedDescription }
                libraryItem = nil
                isProcessing = false
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { data in
                showCamera = false
                isProcessing = true
                Task {
                    do { try await attach(data) }
                    catch { uploadError = error.localizedDescription }
                    isProcessing = false
                }
            } onDismiss: { showCamera = false }
        }
        #endif
        .adaptivePresentation(isPresented: $showPhotoPicker, style: .fullSheet) {
            NotePhotoPicker(photos: photos) { selected in
                reference = NoteVisualReference(spaceId: scope?.spaceId, image: selected)
            }
        }
        .adaptivePresentation(isPresented: $showMarkerEditor, style: .viewer) {
            if let reference {
                NoteReferenceViewer(reference: reference, isEditing: true) { marker in
                    self.reference?.marker = marker
                }
            }
        }
    }

    private func attach(_ data: Data) async throws {
        guard let scope, let accountId = accountContext.currentAccountId else {
            throw CocoaError(.fileWriteNoPermission)
        }
        uploadError = nil
        guard let jpeg = ImageThumbnailGenerator.generateThumbnailData(
            from: data, maxDimension: 2400, quality: 0.85, force: true
        ) else { throw CocoaError(.fileReadCorruptFile) }
        let path = scope.collectionPath(accountId: accountId) + "/photos/" + UUID().uuidString + ".jpg"
        let url = try await mediaService.uploadImage(jpeg, path: path)
        let thumbnails = await mediaService.uploadThumbnails(for: jpeg, originalPath: path, contentType: "image/jpeg")
        let image = AttachmentRef(url: url, thumbnailUrlSm: thumbnails.sm, thumbnailUrlMd: thumbnails.md, contentType: "image/jpeg")
        newUploads.append(image)
        reference = NoteVisualReference(spaceId: scope.spaceId, image: image)
    }

}

struct NoteReferenceViewer: View {
    let reference: NoteVisualReference
    var noteText: String?
    let isEditing: Bool
    var onSave: ((NoteMarker?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var marker: NoteMarker?
    @State private var zoomScale: CGFloat = 1

    init(
        reference: NoteVisualReference,
        noteText: String? = nil,
        isEditing: Bool = false,
        onSave: ((NoteMarker?) -> Void)? = nil
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
            id: "note-marker",
            point: CGPoint(x: marker.x, y: marker.y),
            accessibilityLabel: "Note marker",
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
                        marker = NoteMarker(x: point.x, y: point.y)
                    } : nil
                )
                .background(Color.black)
                .accessibilityLabel("Note photo")
                .accessibilityAction(named: "Place mark at center") {
                    if isEditing { marker = NoteMarker(x: 0.5, y: 0.5) }
                }

                controls
            }
            .navigationTitle(isEditing ? "Mark what you mean" : "Note")
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

    private func coordinate(_ keyPath: WritableKeyPath<NoteMarker, Double>) -> Binding<Double> {
        Binding(
            get: { marker?[keyPath: keyPath] ?? 0.5 },
            set: { marker?[keyPath: keyPath] = $0 }
        )
    }
}

private struct NotePhotoPicker: View {
    let photos: [AttachmentRef]
    let onSelect: (AttachmentRef) -> Void

    @Environment(\.dismiss) private var dismiss

    private var availablePhotos: [AttachmentRef] {
        NotePhotoCatalog.availableImages(photos)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No existing photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Take a photo or choose one from your photo library.")
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
                                .accessibilityLabel("Choose existing photo \(index + 1)")
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .background(BrandColors.background)
            .navigationTitle("Choose existing photo")
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

struct NoteEditor: View {
    let scope: NoteScope?
    let photos: [AttachmentRef]
    let isEditing: Bool
    var header: AnyView?
    let onSave: (String, NoteVisualReference?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var reference: NoteVisualReference?
    @State private var submission = NoteSubmissionState()
    @State private var isProcessing = false
    @State private var newUploads: [AttachmentRef] = []
    @Environment(MediaService.self) private var mediaService
    private var isSaving: Bool { submission.isSaving || submission.didSave }
    @State private var errorMessage: String?

    init(
        scope: NoteScope?,
        photos: [AttachmentRef],
        note: LedgerNote? = nil,
        initialPhoto: AttachmentRef? = nil,
        initialText: String = "",
        header: AnyView? = nil,
        onSave: @escaping (String, NoteVisualReference?) async throws -> Void
    ) {
        self.scope = scope
        self.header = header
        self.photos = photos
        self.isEditing = note != nil
        self.onSave = onSave
        _text = State(initialValue: note?.text ?? initialText)
        _reference = State(initialValue: note?.visualReference ?? initialPhoto.map {
            NoteVisualReference(spaceId: scope?.spaceId, image: $0)
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let header { header }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Note")
                            .font(Typography.label)
                        TextField("Write a note", text: $text, axis: .vertical)
                            .lineLimit(4...12)
                            .formInputStyle()
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Photo")
                            .font(Typography.label)
                        NoteVisualReferenceField(
                            scope: scope,
                            photos: photos,
                            reference: $reference,
                            isProcessing: $isProcessing,
                            newUploads: $newUploads
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Typography.small)
                            .foregroundStyle(.red)
                    }
                }
                .padding(Spacing.screenPadding)
                .disabled(isSaving || isProcessing)
            }
            .navigationTitle(isEditing ? "Edit note" : "Add note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cleanupUploads(keeping: nil)
                        dismiss()
                    }
                    .disabled(isSaving || isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || isProcessing || scope == nil || (trimmedText.isEmpty && reference == nil))
                }
            }
            .interactiveDismissDisabled(isSaving || isProcessing || !newUploads.isEmpty)
            .onChange(of: scope) { _, _ in
                cleanupUploads(keeping: nil)
                reference = nil
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard scope != nil, !isProcessing, !isSaving,
              !trimmedText.isEmpty || reference != nil else { return }
        let savedText = trimmedText
        let savedReference = reference
        Task {
            do {
                if try await submission.save({ try await onSave(savedText, savedReference) }) {
                    cleanupUploads(keeping: savedReference?.image.url)
                    dismiss()
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func cleanupUploads(keeping url: String?) {
        let discarded = newUploads.filter { $0.url != url }
        newUploads = []
        Task {
            for image in discarded {
                for path in [image.url, image.thumbnailUrlSm, image.thumbnailUrlMd].compactMap({ $0 }) {
                    try? await mediaService.deleteImage(url: path)
                }
            }
        }
    }
}

/// The same note card in every scope.
struct NoteCard: View {
    let note: LedgerNote
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onViewPhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                if !note.text.isEmpty {
                    SelectableNoteText(text: note.text, style: .body)
                }
                Spacer(minLength: 0)
                if note.id != nil {
                    Menu {
                        Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let reference = note.visualReference {
                Button(action: onViewPhoto) {
                    NoteReferenceThumbnail(reference: reference, height: 150)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Spacing.sm) {
                if !note.createdByName.isEmpty { Text(note.createdByName) }
                if let date = note.createdAt { Text(date, style: .relative) }
                if note.updatedAt != nil { Text("Edited") }
            }
            .font(Typography.caption)
            .foregroundStyle(BrandColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        }
    }
}
