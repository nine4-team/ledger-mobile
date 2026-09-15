import SwiftUI

// Original pinned-image chrome, with data and actions supplied by its owner.
struct PinnedImagePresentation<ImageContent: View, Actions: View>: View {
    let imageCount: Int
    @Binding var currentIndex: Int
    @Binding var zoomScale: CGFloat
    let onClose: () -> Void
    let onChangeImage: (Int) -> Void
    var isInteractionDisabled: Bool = false
    var accessibilityPrefix = "pinned"
    var closeAccessibilityIdentifier: String? = nil
    var allowsSwipePaging = false
    @ViewBuilder var imageContent: () -> ImageContent
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            imageContent()
            VStack {
                HStack {
                    actions()
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                Spacer()
            }
            if imageCount > 1 {
                VStack {
                    Spacer()
                    HStack {
                        imageCounter
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                }
            }
        }
        .simultaneousGesture(DragGesture().onEnded { value in
            guard allowsSwipePaging, !isInteractionDisabled, zoomScale <= 1.01,
                  imageCount > 1, abs(value.translation.width) > 40,
                  abs(value.translation.width) > abs(value.translation.height) else { return }
            let index = value.translation.width < 0
                ? MediaGalleryCalculations.nextIndex(current: currentIndex, total: imageCount)
                : MediaGalleryCalculations.previousIndex(current: currentIndex, total: imageCount)
            currentIndex = index
            zoomScale = 1
            onChangeImage(index)
        })
    }

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
        .accessibilityIdentifier(closeAccessibilityIdentifier ?? (accessibilityPrefix + "-image-unpin"))
    }

    private var imageCounter: some View {
        HStack(spacing: Spacing.md) {
            Button {
                let prev = MediaGalleryCalculations.previousIndex(current: currentIndex, total: imageCount)
                currentIndex = prev
                zoomScale = 1.0
                onChangeImage(prev)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            .accessibilityLabel("Previous")
            .accessibilityIdentifier(accessibilityPrefix + "-images-previous")

            Text(MediaGalleryCalculations.imageCounterLabel(currentIndex: currentIndex, total: imageCount))
                .accessibilityIdentifier(accessibilityPrefix + "-images-counter")
                .font(Typography.small)
                .foregroundStyle(.white)

            Button {
                let next = MediaGalleryCalculations.nextIndex(current: currentIndex, total: imageCount)
                currentIndex = next
                zoomScale = 1.0
                onChangeImage(next)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Next")
            .accessibilityIdentifier(accessibilityPrefix + "-images-next")
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.lg)
        .background(.black.opacity(0.7))
        .clipShape(Capsule())
        .disabled(isInteractionDisabled)
        .opacity(!isInteractionDisabled ? 1 : 0.55)
    }
}
