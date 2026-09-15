import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MediaGallerySection: View {
    let title: String
    let attachments: [AttachmentRef]
    var maxAttachments: Int = 50
    var allowedKinds: [AttachmentKind] = [.image, .pdf]
    /// Called when the user confirms image selection. Receives image data; caller should upload
    /// via MediaService and append the resulting AttachmentRef to the entity's images array.
    var onUploadAttachment: ((Data) async throws -> Void)?
    var onUploadAttachmentFile: ((AttachmentUpload) async throws -> Void)?
    var onUploadDocument: ((Data, String) async throws -> Void)?
    var sourceImages: [AttachmentRef] = []
    var sourceImagesTitle: String = "Transaction Images"
    var onAddSourceImages: (([AttachmentRef]) -> Void)?
    var onRemoveAttachment: ((AttachmentRef) -> Void)?
    var onSetPrimary: ((AttachmentRef) -> Void)?
    var onPinImage: ((AttachmentRef) -> Void)?
    var onSaveImage: ((AttachmentRef) async throws -> Void)? = ImageSaveHelper.saveToDevice

    @State private var showGallery = false
    @State private var galleryIndex: Int = 0
    @State private var showAttachmentMenu = false
    @State private var selectedAttachment: AttachmentRef?
    @State private var menuPendingAction: (() -> Void)?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showAddSourceMenu = false
    @State private var showPDFViewer = false
    @State private var selectedPDFAttachment: AttachmentRef?
    @State private var showSourceImagePicker = false
    @State private var selectedSourceImageUrls: Set<String> = []
    @State private var saveAlertMessage: String?

    private var canAdd: Bool {
        MediaGalleryCalculations.canAddAttachment(current: attachments, maxAttachments: maxAttachments)
    }

    private var canUploadImages: Bool {
        onUploadAttachment != nil || onUploadAttachmentFile != nil
    }

    private var displayAttachments: [AttachmentRef] {
        attachments.filter { allowedKinds.contains($0.kind) }
    }

    private var imageOnlyAttachments: [AttachmentRef] {
        attachments.filter { $0.kind == .image }
    }

    private var hasOptionsButton: Bool {
        MediaGalleryCalculations.shouldShowOptionsButton(
            hasSetPrimary: onSetPrimary != nil,
            hasRemove: onRemoveAttachment != nil
        )
        || onPinImage != nil
        || onSaveImage != nil
    }

    private var remainingSlots: Int {
        max(0, maxAttachments - attachments.count)
    }

    private var availableSourceImages: [AttachmentRef] {
        let existingUrls = Set(attachments.map(\.url))
        var seenSourceUrls = Set<String>()
        return sourceImages.compactMap { attachment in
            guard attachment.kind == .image,
                  !attachment.url.isEmpty,
                  !existingUrls.contains(attachment.url),
                  seenSourceUrls.insert(attachment.url).inserted else {
                return nil
            }
            return attachment
        }
        .prefix(remainingSlots)
        .map { $0 }
    }

    var body: some View {
        Group {
            if title.isEmpty {
                Card {
                    galleryBody
                }
            } else {
                TitledCard(title: title) {
                    galleryBody
                } headerAction: {
                    // The empty state shows a prominent centered Add CTA, so the
                    // header link is reserved for when there's already content.
                    if canAdd, canUploadImages, !attachments.isEmpty {
                        if isUploading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Add") {
                                showAddSourceMenu = true
                            }
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.primary)
                        }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showGallery) {
            ImageGallery(
                images: imageOnlyAttachments,
                initialIndex: galleryIndex,
                isPresented: $showGallery,
                onPinImage: onPinImage,
                onSaveImage: onSaveImage
            )
        }
        .fullScreenCover(isPresented: $showPDFViewer) {
            if let attachment = selectedPDFAttachment {
                PDFViewerSheet(attachment: attachment, isPresented: $showPDFViewer, onPinImage: onPinImage)
            }
        }
        #else
        .adaptivePresentation(isPresented: $showGallery, style: .viewer) {
            ImageGallery(
                images: imageOnlyAttachments,
                initialIndex: galleryIndex,
                isPresented: $showGallery,
                onPinImage: onPinImage,
                onSaveImage: onSaveImage
            )
        }
        .adaptivePresentation(isPresented: $showPDFViewer, style: .viewer) {
            if let attachment = selectedPDFAttachment {
                PDFViewerSheet(attachment: attachment, isPresented: $showPDFViewer, onPinImage: onPinImage)
            }
        }
        #endif
        .adaptivePresentation(isPresented: $showAttachmentMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
            selectedAttachment = nil
        }) {
            if let attachment = selectedAttachment {
                attachmentMenu(for: attachment)
            }
        }
        .modifier(MediaCapturePresentation(showAddSourceMenu: $showAddSourceMenu,
            isUploading: $isUploading, uploadError: $uploadError, remainingSlots: remainingSlots,
            allowedKinds: allowedKinds, onUploadAttachment: onUploadAttachment,
            onUploadAttachmentFile: onUploadAttachmentFile, onUploadDocument: onUploadDocument,
            sourceImagesTitle: sourceImagesTitle,
            onSelectSourceImages: onAddSourceImages != nil && !availableSourceImages.isEmpty
                ? { showSourceImagePicker = true } : nil))
        .adaptivePresentation(isPresented: $showSourceImagePicker, style: .fullSheet) {
            SourceImagePickerModal(
                title: sourceImagesTitle,
                attachments: availableSourceImages,
                selectedUrls: $selectedSourceImageUrls,
                onAdd: { selected in
                    onAddSourceImages?(selected)
                    selectedSourceImageUrls = []
                    showSourceImagePicker = false
                }
            )
        }
        .alert("Image", isPresented: .init(
            get: { saveAlertMessage != nil },
            set: { if !$0 { saveAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveAlertMessage = nil }
        } message: {
            Text(saveAlertMessage ?? "")
        }
    }

    @ViewBuilder
    private var galleryBody: some View {
        VStack(spacing: Spacing.sm) {
            if attachments.isEmpty {
                emptyState
            } else {
                galleryContent
            }

            if let uploadError {
                Text(uploadError)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if canAdd, canUploadImages {
                if isUploading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.xl)
                } else {
                    Button { showAddSourceMenu = true } label: {
                        RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .foregroundStyle(BrandColors.borderSecondary)
                            .frame(width: 140, height: 140)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 32, weight: .regular))
                                    .foregroundStyle(BrandColors.textSecondary)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
                }
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(BrandColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xl)
            }
        }
    }

    // MARK: - Gallery Content

    private var galleryContent: some View {
        ThumbnailGrid(
            attachments: displayAttachments,
            showPrimaryBadge: true,
            showOptionsButton: hasOptionsButton,
            showAddTile: canAdd && canUploadImages,
            onThumbnailTap: { index in
                guard index < displayAttachments.count else { return }
                let attachment = displayAttachments[index]
                if attachment.kind == .pdf {
                    selectedPDFAttachment = attachment
                    showPDFViewer = true
                } else {
                    // Map display index to image-only index for the pager
                    let imageIndex = imageOnlyAttachments.firstIndex(where: { $0.url == attachment.url }) ?? 0
                    galleryIndex = imageIndex
                    showGallery = true
                }
            },
            onOptionsButtonTap: { index in
                guard index < displayAttachments.count else { return }
                selectedAttachment = displayAttachments[index]
                showAttachmentMenu = true
            },
            onAddTap: {
                showAddSourceMenu = true
            }
        )
    }

    // MARK: - Attachment Menu

    private func attachmentMenu(for attachment: AttachmentRef) -> some View {
        var items: [ActionMenuItem] = []

        // Open in viewer
        if attachment.kind == .pdf {
            items.append(ActionMenuItem(
                id: "open",
                label: "Open",
                icon: "arrow.up.left.and.arrow.down.right",
                onPress: { [self] in
                    selectedPDFAttachment = attachment
                    showPDFViewer = true
                }
            ))
        } else if let index = imageOnlyAttachments.firstIndex(where: { $0.url == attachment.url }) {
            items.append(ActionMenuItem(
                id: "open",
                label: "Open",
                icon: "arrow.up.left.and.arrow.down.right",
                onPress: { [self] in
                    galleryIndex = index
                    showGallery = true
                }
            ))
        }

        if onSetPrimary != nil,
           MediaGalleryCalculations.shouldOfferSetPrimary(for: attachment, in: attachments) {
            items.append(ActionMenuItem(
                id: "set-primary",
                label: "Set as Primary",
                icon: "star",
                onPress: { [onSetPrimary] in
                    onSetPrimary?(attachment)
                }
            ))
        }

        if let onPinImage, PinnedImageCalculations.canPin(attachment) {
            items.append(ActionMenuItem(
                id: "pin",
                label: attachment.kind == .pdf ? "Pin PDF" : "Pin Image",
                icon: "pin",
                onPress: {
                    onPinImage(attachment)
                }
            ))
        }

        if attachment.kind == .image, onSaveImage != nil {
            items.append(ActionMenuItem(
                id: "save",
                label: "Save to Device",
                icon: "square.and.arrow.down",
                onPress: {
                    saveImage(attachment)
                }
            ))
        }

        if onRemoveAttachment != nil {
            items.append(ActionMenuItem(
                id: "remove",
                label: "Remove",
                icon: "trash",
                isDestructive: true,
                onPress: { [onRemoveAttachment] in
                    onRemoveAttachment?(attachment)
                }
            ))
        }

        return ActionMenuSheet(
            title: attachment.fileName ?? "Attachment",
            items: items,
            onSelectAction: { action in
                menuPendingAction = action
            }
        )
    }

    private func saveImage(_ attachment: AttachmentRef) {
        guard let onSaveImage else { return }
        Task {
            do {
                try await onSaveImage(attachment)
                saveAlertMessage = "Image saved to Photos."
            } catch {
                saveAlertMessage = error.localizedDescription
            }
        }
    }
}

private struct SourceImagePickerModal: View {
    let title: String
    let attachments: [AttachmentRef]
    @Binding var selectedUrls: Set<String>
    let onAdd: ([AttachmentRef]) -> Void

    @Environment(\.dismiss) private var dismiss

    private var selectedAttachments: [AttachmentRef] {
        attachments.filter { selectedUrls.contains($0.url) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if attachments.isEmpty {
                        Text("No available images.")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Spacing.xl)
                    } else {
                        SelectableImageGrid(
                            attachments: attachments,
                            selectedUrls: $selectedUrls
                        )
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedUrls.isEmpty {
                    bottomBar
                }
            }
            .background(BrandColors.background)
            .navigationTitle(title)
            .navBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedUrls = []
                        dismiss()
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Clear") {
                selectedUrls = []
            }
            .font(Typography.label)
            .foregroundStyle(BrandColors.textSecondary)

            Spacer()

            AppButton(title: "Add \(selectedUrls.count)") {
                onAdd(selectedAttachments)
            }
            .fixedSize()
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(BrandColors.background)
    }
}


// MARK: - Previews

#Preview("Empty") {
    MediaGallerySection(
        title: "IMAGES",
        attachments: [],
        onUploadAttachment: { _ in },
        onUploadDocument: { _, _ in }
    )
    .padding(Spacing.screenPadding)
}

#Preview("With Images") {
    MediaGallerySection(
        title: "IMAGES",
        attachments: [
            AttachmentRef(url: "https://picsum.photos/200/200?1", isPrimary: true),
            AttachmentRef(url: "https://picsum.photos/200/200?2"),
            AttachmentRef(url: "https://picsum.photos/200/200?3"),
        ],
        onUploadAttachment: { _ in },
        onRemoveAttachment: { _ in },
        onSetPrimary: { _ in }
    )
    .padding(Spacing.screenPadding)
}

#Preview("At Max Limit") {
    MediaGallerySection(
        title: "IMAGES",
        attachments: (1...10).map { i in
            AttachmentRef(url: "https://picsum.photos/200/200?\(i)", isPrimary: i == 1)
        },
        maxAttachments: 10,
        onRemoveAttachment: { _ in },
        onSetPrimary: { _ in }
    )
    .padding(Spacing.screenPadding)
}
