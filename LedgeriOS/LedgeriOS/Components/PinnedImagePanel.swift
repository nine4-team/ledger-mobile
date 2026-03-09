import SwiftUI

/// Persistent reference panel that displays a pinned image with zoom/pan support.
/// Used inside `PinnedImageLayout` on detail screens so users can reference an image
/// while editing fields.
struct PinnedImagePanel: View {
    let attachment: AttachmentRef
    let allImages: [AttachmentRef]
    let onClose: () -> Void
    let onChangeImage: (AttachmentRef) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZoomableScrollView(
                url: URL(string: allImages.indices.contains(currentIndex) ? allImages[currentIndex].url : attachment.url),
                zoomScale: $zoomScale,
                onSingleTap: nil
            )

            // Close button — top trailing
            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }

            // Image counter — bottom center
            if allImages.count > 1 {
                VStack {
                    Spacer()
                    imageCounter
                        .padding(.bottom, Spacing.sm)
                }
            }
        }
        .onAppear {
            currentIndex = allImages.firstIndex(where: { $0.url == attachment.url }) ?? 0
        }
        .onChange(of: attachment.url) { _, newURL in
            zoomScale = 1.0
            currentIndex = allImages.firstIndex(where: { $0.url == newURL }) ?? 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned reference image")
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel("Unpin image")
    }

    // MARK: - Image Counter

    private var imageCounter: some View {
        HStack(spacing: Spacing.md) {
            Button {
                let prev = MediaGalleryCalculations.previousIndex(current: currentIndex, total: allImages.count)
                currentIndex = prev
                zoomScale = 1.0
                onChangeImage(allImages[prev])
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: allImages.count))
                .font(Typography.small)
                .foregroundStyle(.white)

            Button {
                let next = MediaGalleryCalculations.nextIndex(current: currentIndex, total: allImages.count)
                currentIndex = next
                zoomScale = 1.0
                onChangeImage(allImages[next])
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.lg)
        .background(.black.opacity(0.7))
        .clipShape(Capsule())
    }
}
