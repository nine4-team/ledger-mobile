import SwiftUI

/// Shared original upload-state treatment; a clock means queued, not uploading.
struct AttachmentUploadStatusOverlay: View {
    let icon: String?
    var body: some View {
        RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
            .fill(.black.opacity(0.35))
            .overlay {
                if let icon { Image(systemName: icon).font(.title2).foregroundStyle(.white) }
                else { ProgressView().tint(.white) }
            }
    }
}

/// Original grid layout; its owner supplies authorized thumbnails and upload state.
struct ThumbnailGridPresentation<Thumbnail: View, Upload: View>: View {
    let count: Int
    var columns: Int = 3
    var showPrimaryBadge: Bool = true
    var showOptionsButton: Bool = false
    var showAddTile: Bool = false
    var isPrimary: (Int) -> Bool
    @ViewBuilder var thumbnail: (Int) -> Thumbnail
    @ViewBuilder var upload: (Int) -> Upload
    var onThumbnailTap: ((Int) -> Void)?
    var onOptionsButtonTap: ((Int) -> Void)?
    var onAddTap: (() -> Void)?

    private var totalItemCount: Int {
        count + (showAddTile ? 1 : 0)
    }

    private var gridItems: [GridItem] {
        #if os(macOS)
        let item = GridItem(.flexible(maximum: 150), spacing: Spacing.sm)
        #else
        let item = GridItem(.flexible(), spacing: Spacing.sm)
        #endif
        return Array(
            repeating: item,
            count: MediaGalleryCalculations.gridColumns(for: totalItemCount, preferredColumns: columns)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: Spacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                thumbnailCell(index: index)
            }

            if showAddTile {
                addTile
            }
        }
    }

    // MARK: - Add Tile

    private var addTile: some View {
        Button {
            onAddTap?()
        } label: {
            RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(BrandColors.borderSecondary)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(BrandColors.textSecondary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Attachment")
    }

    @ViewBuilder
    private func thumbnailCell(index: Int) -> some View {
        let isPrimary = showPrimaryBadge && isPrimary(index)

        Color(BrandColors.surfaceTertiary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                thumbnail(index)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2))
        .overlay {
            if isPrimary {
                RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
                    .strokeBorder(BrandColors.primary, lineWidth: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if isPrimary {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(BrandColors.primary)
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showOptionsButton {
                Button {
                    onOptionsButtonTap?(index)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(BrandColors.primary.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .overlay {
            upload(index)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onThumbnailTap?(index)
        }
    }

}

#if canImport(FirebaseFirestore)
struct ThumbnailGrid: View {
    let attachments: [AttachmentRef]
    var columns: Int = 3
    var showPrimaryBadge: Bool = true
    var showOptionsButton: Bool = false
    var showAddTile: Bool = false
    var uploadStatuses: [String: UploadStatus] = [:]
    var onThumbnailTap: ((Int) -> Void)?
    var onOptionsButtonTap: ((Int) -> Void)?
    var onAddTap: (() -> Void)?

    var body: some View {
        ThumbnailGridPresentation(count: attachments.count, columns: columns,
            showPrimaryBadge: showPrimaryBadge, showOptionsButton: showOptionsButton, showAddTile: showAddTile,
            isPrimary: { attachments[$0].isPrimary == true }, thumbnail: { index in
                let attachment = attachments[index]
                if attachment.kind == .pdf { PDFThumbnailTile(fileName: attachment.fileName) }
                else {
                    FirebaseImage(url: attachment.url, thumbnailUrl: attachment.thumbnailUrlSm, contentMode: .fill) {
                        ProgressView()
                    }
                }
            }, upload: { index in
                if let status = uploadStatuses[attachments[index].url],
                   MediaGalleryCalculations.shouldShowUploadOverlay(status: status) {
                    AttachmentUploadStatusOverlay(icon: MediaGalleryCalculations.uploadOverlayIcon(status: status))
                }
            }, onThumbnailTap: onThumbnailTap, onOptionsButtonTap: onOptionsButtonTap, onAddTap: onAddTap)
    }
}

#Preview("1 Image") {
    ThumbnailGrid(attachments: [
        AttachmentRef(url: "https://picsum.photos/200", kind: .image, isPrimary: true),
    ])
    .padding()
}

#Preview("3 Images with Primary + Options") {
    ThumbnailGrid(
        attachments: [
            AttachmentRef(url: "https://picsum.photos/201", kind: .image, isPrimary: true),
            AttachmentRef(url: "https://picsum.photos/202", kind: .image),
            AttachmentRef(url: "https://picsum.photos/203", kind: .image),
        ],
        showOptionsButton: true,
        onOptionsButtonTap: { _ in }
    )
    .padding()
}

#Preview("6+ Images") {
    ThumbnailGrid(attachments: (1...7).map { i in
        AttachmentRef(url: "https://picsum.photos/20\(i)", kind: .image, isPrimary: i == 1)
    })
    .padding()
}

#Preview("Empty") {
    ThumbnailGrid(attachments: [])
        .padding()
}
#endif
