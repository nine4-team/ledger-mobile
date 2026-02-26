import SwiftUI

struct ThumbnailGrid: View {
    let attachments: [AttachmentRef]
    var columns: Int = 3
    var showPrimaryBadge: Bool = true
    var onThumbnailTap: ((Int) -> Void)?

    private var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Spacing.sm),
            count: MediaGalleryCalculations.gridColumns(for: attachments.count, preferredColumns: columns)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: Spacing.sm) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                thumbnailCell(attachment: attachment, index: index)
            }
        }
    }

    @ViewBuilder
    private func thumbnailCell(attachment: AttachmentRef, index: Int) -> some View {
        Button {
            onThumbnailTap?(index)
        } label: {
            AsyncImage(url: URL(string: attachment.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder(systemName: "exclamationmark.triangle")
                case .empty:
                    placeholder(systemName: "photo")
                @unknown default:
                    placeholder(systemName: "photo")
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2))
            .overlay(alignment: .topLeading) {
                if showPrimaryBadge && attachment.isPrimary == true {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(BrandColors.primary)
                        .clipShape(Circle())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func placeholder(systemName: String) -> some View {
        Color(BrandColors.surfaceTertiary)
            .overlay {
                Image(systemName: systemName)
                    .foregroundStyle(BrandColors.textTertiary)
            }
    }
}

#Preview("1 Image") {
    ThumbnailGrid(attachments: [
        AttachmentRef(url: "https://picsum.photos/200", kind: .image, isPrimary: true),
    ])
    .padding()
}

#Preview("3 Images with Primary") {
    ThumbnailGrid(attachments: [
        AttachmentRef(url: "https://picsum.photos/201", kind: .image, isPrimary: true),
        AttachmentRef(url: "https://picsum.photos/202", kind: .image),
        AttachmentRef(url: "https://picsum.photos/203", kind: .image),
    ])
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
