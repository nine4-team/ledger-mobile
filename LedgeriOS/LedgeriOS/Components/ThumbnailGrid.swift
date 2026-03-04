import SwiftUI

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

    private var totalItemCount: Int {
        attachments.count + (showAddTile ? 1 : 0)
    }

    private var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Spacing.sm),
            count: MediaGalleryCalculations.gridColumns(for: totalItemCount, preferredColumns: columns)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: Spacing.sm) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                thumbnailCell(attachment: attachment, index: index)
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
    }

    @ViewBuilder
    private func thumbnailCell(attachment: AttachmentRef, index: Int) -> some View {
        let isPrimary = showPrimaryBadge && attachment.isPrimary == true

        Color(BrandColors.surfaceTertiary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: URL(string: attachment.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(BrandColors.textTertiary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "photo")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
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
            if let status = uploadStatuses[attachment.url],
               MediaGalleryCalculations.shouldShowUploadOverlay(status: status) {
                RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
                    .fill(.black.opacity(0.35))
                    .overlay {
                        if let icon = MediaGalleryCalculations.uploadOverlayIcon(status: status) {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(.white)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onThumbnailTap?(index)
        }
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
