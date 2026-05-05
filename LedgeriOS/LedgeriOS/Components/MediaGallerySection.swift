import SwiftUI
import PhotosUI

struct MediaGallerySection: View {
    let title: String
    let attachments: [AttachmentRef]
    var maxAttachments: Int = 50
    var allowedKinds: [AttachmentKind] = [.image, .pdf]
    /// Called when the user confirms image selection. Receives JPEG data; caller should upload
    /// via MediaService and append the resulting AttachmentRef to the entity's images array.
    var onUploadAttachment: ((Data) async throws -> Void)?
    var onRemoveAttachment: ((AttachmentRef) -> Void)?
    var onSetPrimary: ((AttachmentRef) -> Void)?
    var onPinImage: ((AttachmentRef) -> Void)?

    @State private var showGallery = false
    @State private var galleryIndex: Int = 0
    @State private var showAttachmentMenu = false
    @State private var selectedAttachment: AttachmentRef?
    @State private var menuPendingAction: (() -> Void)?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showAddSourceMenu = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showPDFViewer = false
    @State private var selectedPDFAttachment: AttachmentRef?

    private var canAdd: Bool {
        MediaGalleryCalculations.canAddAttachment(current: attachments, maxAttachments: maxAttachments)
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
    }

    private var remainingSlots: Int {
        max(0, maxAttachments - attachments.count)
    }

    var body: some View {
        TitledCard(title: title) {
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
        } headerAction: {
            // The empty state shows a prominent centered Add CTA, so the
            // header link is reserved for when there's already content.
            if canAdd, onUploadAttachment != nil, !attachments.isEmpty {
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
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showGallery) {
            ImageGallery(
                images: imageOnlyAttachments,
                initialIndex: galleryIndex,
                isPresented: $showGallery,
                onPinImage: onPinImage
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
                onPinImage: onPinImage
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
        .adaptivePresentation(isPresented: $showAddSourceMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            addSourceMenu
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { imageData in
                Task {
                    await handlePickedImageData(imageData)
                }
            } onDismiss: {
                showCamera = false
            }
        }
        #endif
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: remainingSlots,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    await handlePickedItem(item)
                }
                pickerItems = []
            }
        }
    }

    // MARK: - Photo Picker Handling

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            await handlePickedImageData(data)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func handlePickedImageData(_ data: Data) async {
        guard let onUploadAttachment else { return }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }

        do {
            try await onUploadAttachment(data)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if canAdd, onUploadAttachment != nil {
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
            showAddTile: canAdd && onUploadAttachment != nil,
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

    // MARK: - Add Source Menu

    private var addSourceMenu: some View {
        ActionMenuSheet(
            title: "Add Image",
            items: [
                ActionMenuItem(
                    id: "camera",
                    label: "Camera",
                    icon: "camera.fill",
                    onPress: {
                        showCamera = true
                    }
                ),
                ActionMenuItem(
                    id: "photo-library",
                    label: "Photo Library",
                    icon: "photo.on.rectangle",
                    onPress: {
                        showPhotoPicker = true
                    }
                ),
            ],
            onSelectAction: { action in
                menuPendingAction = action
            }
        )
    }

    // MARK: - Attachment Menu

    private func attachmentMenu(for attachment: AttachmentRef) -> some View {
        let isPrimary = attachment.isPrimary ?? false
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

        if !isPrimary, onSetPrimary != nil {
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
}

// MARK: - Previews

#Preview("Empty") {
    MediaGallerySection(
        title: "IMAGES",
        attachments: [],
        onUploadAttachment: { _ in }
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
