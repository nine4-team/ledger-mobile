import SwiftUI
import PhotosUI

struct MediaGallerySection: View {
    let title: String
    let attachments: [AttachmentRef]
    var maxAttachments: Int = 10
    var allowedKinds: [AttachmentKind] = [.image]
    /// Called when the user confirms image selection. Receives JPEG data; caller should upload
    /// via MediaService and append the resulting AttachmentRef to the entity's images array.
    var onUploadAttachment: ((Data) async throws -> Void)?
    var onRemoveAttachment: ((AttachmentRef) -> Void)?
    var onSetPrimary: ((AttachmentRef) -> Void)?
    var emptyStateMessage: String = "No images yet"

    @State private var showGallery = false
    @State private var galleryIndex: Int = 0
    @State private var showAttachmentMenu = false
    @State private var selectedAttachment: AttachmentRef?
    @State private var menuPendingAction: (() -> Void)?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var uploadError: String?

    private var canAdd: Bool {
        MediaGalleryCalculations.canAddAttachment(current: attachments, maxAttachments: maxAttachments)
    }

    private var imageAttachments: [AttachmentRef] {
        attachments.filter { $0.kind == .image }
    }

    var body: some View {
        TitledCard(title: title) {
            if attachments.isEmpty {
                emptyState
            } else {
                galleryContent
            }
        } headerAction: {
            if canAdd, onUploadAttachment != nil {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    if isUploading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Add")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.primary)
                    }
                }
                .disabled(isUploading)
            }
        }
        .fullScreenCover(isPresented: $showGallery) {
            ImageGallery(
                images: imageAttachments,
                initialIndex: galleryIndex,
                isPresented: $showGallery
            )
        }
        .sheet(isPresented: $showAttachmentMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
            selectedAttachment = nil
        }) {
            if let attachment = selectedAttachment {
                attachmentMenu(for: attachment)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handlePickedItem(newItem)
                pickerItem = nil
            }
        }
    }

    // MARK: - Photo Picker Handling

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let onUploadAttachment else { return }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try await onUploadAttachment(data)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text(emptyStateMessage)
            .font(Typography.small)
            .foregroundStyle(BrandColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Spacing.xl)
    }

    // MARK: - Gallery Content

    private var galleryContent: some View {
        ThumbnailGrid(
            attachments: imageAttachments,
            showPrimaryBadge: true,
            onThumbnailTap: { index in
                galleryIndex = index
                showGallery = true
            }
        )
        .onLongPressGesture(minimumDuration: 0) {} // no-op for default
    }

    // MARK: - Attachment Menu

    private func attachmentMenu(for attachment: AttachmentRef) -> some View {
        let isPrimary = attachment.isPrimary ?? false
        var items: [ActionMenuItem] = []

        if !isPrimary {
            items.append(ActionMenuItem(
                id: "set-primary",
                label: "Set as Primary",
                icon: "star",
                onPress: { [onSetPrimary] in
                    onSetPrimary?(attachment)
                }
            ))
        }

        items.append(ActionMenuItem(
            id: "remove",
            label: "Remove",
            icon: "trash",
            isDestructive: true,
            onPress: { [onRemoveAttachment] in
                onRemoveAttachment?(attachment)
            }
        ))

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
        attachments: []
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
