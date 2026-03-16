import SwiftUI

struct SelectableImageGrid: View {
    let attachments: [AttachmentRef]
    @Binding var selectedUrls: Set<String>

    private var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Spacing.sm),
            count: MediaGalleryCalculations.gridColumns(for: attachments.count, preferredColumns: 3)
        )
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: Spacing.sm) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                selectableCell(attachment: attachment)
            }
        }
    }

    @ViewBuilder
    private func selectableCell(attachment: AttachmentRef) -> some View {
        let isSelected = selectedUrls.contains(attachment.url)

        Color(BrandColors.surfaceTertiary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                FirebaseImage(url: attachment.url, thumbnailUrl: attachment.thumbnailUrlSm, contentMode: .fill) {
                    ProgressView()
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Dimensions.cardRadius / 2)
                        .strokeBorder(BrandColors.primary, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(BrandColors.primary)
                        .background(Circle().fill(.white).padding(2))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if selectedUrls.contains(attachment.url) {
                        selectedUrls.remove(attachment.url)
                    } else {
                        selectedUrls.insert(attachment.url)
                    }
                }
            }
    }
}

#Preview("3 Images") {
    @Previewable @State var selected: Set<String> = ["https://picsum.photos/201"]
    SelectableImageGrid(
        attachments: [
            AttachmentRef(url: "https://picsum.photos/201", kind: .image),
            AttachmentRef(url: "https://picsum.photos/202", kind: .image),
            AttachmentRef(url: "https://picsum.photos/203", kind: .image),
        ],
        selectedUrls: $selected
    )
    .padding()
}

#Preview("6 Images") {
    @Previewable @State var selected: Set<String> = []
    SelectableImageGrid(
        attachments: (1...6).map { i in
            AttachmentRef(url: "https://picsum.photos/20\(i)", kind: .image)
        },
        selectedUrls: $selected
    )
    .padding()
}
