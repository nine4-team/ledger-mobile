import SwiftUI

/// Adaptive layout that conditionally shows a pinned image panel alongside content.
///
/// - **iPhone (compact width):** Resizable top panel with drag handle, content scrolls below.
/// - **iPad (regular width):** Leading sidebar at fixed width, content fills remaining space.
/// - **No pin:** Passes content through unchanged.
struct PinnedImageLayout<Content: View>: View {
    let pinnedAttachment: AttachmentRef?
    let allImages: [AttachmentRef]
    let onClose: () -> Void
    let onChangeImage: (AttachmentRef) -> Void
    var onUpdateCheckmarks: ((AttachmentRef, [ImageCheckmark]) -> Void)? = nil
    var isMatchingItems: Bool = false
    var pendingItemId: String? = nil
    var pendingItemName: String? = nil
    var onToggleItemMatching: (() -> Void)? = nil
    var onCancelPendingItemMatch: (() -> Void)? = nil
    var onPlaceItemCheckmark: ((AttachmentRef, String, CGPoint) -> Void)? = nil
    var itemNameForId: ((String) -> String?)? = nil
    var onMoveItemCheckmark: ((String) -> Void)? = nil
    var onClearAllCheckmarks: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var panelHeightFraction: CGFloat = 0.33
    @GestureState private var dragStartFraction: CGFloat?

    private let minFraction: CGFloat = 0.20
    private let maxFraction: CGFloat = 0.50

    var body: some View {
        if let attachment = pinnedAttachment {
            if sizeClass == .regular {
                iPadLayout(attachment: attachment)
            } else {
                iPhoneLayout(attachment: attachment)
            }
        } else {
            content()
        }
    }

    // MARK: - iPhone Layout (vertical split)

    private func iPhoneLayout(attachment: AttachmentRef) -> some View {
        GeometryReader { geometry in
            let panelHeight = max(geometry.size.height * panelHeightFraction, 100)
            VStack(spacing: 0) {
                PinnedImagePanel(
                    attachment: attachment,
                    allImages: allImages,
                    onClose: onClose,
                    onChangeImage: onChangeImage,
                    onUpdateCheckmarks: onUpdateCheckmarks,
                    isMatchingItems: isMatchingItems,
                    pendingItemId: pendingItemId,
                    pendingItemName: pendingItemName,
                    onToggleItemMatching: onToggleItemMatching,
                    onCancelPendingItemMatch: onCancelPendingItemMatch,
                    onPlaceItemCheckmark: onPlaceItemCheckmark,
                    itemNameForId: itemNameForId,
                    onMoveItemCheckmark: onMoveItemCheckmark,
                    onClearAllCheckmarks: onClearAllCheckmarks
                )
                .frame(height: panelHeight)
                .id(attachment.url)
                .transition(.opacity)

                resizeHandle(totalHeight: geometry.size.height)

                content()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pinnedAttachment?.url)
        }
    }

    // MARK: - iPad Layout (leading sidebar)

    private func iPadLayout(attachment: AttachmentRef) -> some View {
        GeometryReader { geometry in
            let sidebarWidth = max(
                geometry.size.width - Dimensions.contentMaxWidth,
                Dimensions.pinnedSidebarWidth
            )
            HStack(spacing: 0) {
                PinnedImagePanel(
                    attachment: attachment,
                    allImages: allImages,
                    onClose: onClose,
                    onChangeImage: onChangeImage,
                    onUpdateCheckmarks: onUpdateCheckmarks,
                    isMatchingItems: isMatchingItems,
                    pendingItemId: pendingItemId,
                    pendingItemName: pendingItemName,
                    onToggleItemMatching: onToggleItemMatching,
                    onCancelPendingItemMatch: onCancelPendingItemMatch,
                    onPlaceItemCheckmark: onPlaceItemCheckmark,
                    itemNameForId: itemNameForId,
                    onMoveItemCheckmark: onMoveItemCheckmark,
                    onClearAllCheckmarks: onClearAllCheckmarks
                )
                .frame(width: sidebarWidth)
                .id(attachment.url)
                .transition(.opacity)

                Divider()

                content()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pinnedAttachment?.url)
        }
    }

    // MARK: - Resize Handle

    private func resizeHandle(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Divider()
            Rectangle()
                .fill(Color.clear)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    Capsule()
                        .fill(BrandColors.textTertiary)
                        .frame(width: 36, height: 4)
                }
                .gesture(
                    DragGesture()
                        .updating($dragStartFraction) { _, state, _ in
                            if state == nil { state = panelHeightFraction }
                        }
                        .onChanged { value in
                            guard let start = dragStartFraction, totalHeight > 0 else { return }
                            let newFraction = start + value.translation.height / totalHeight
                            panelHeightFraction = PinnedImageCalculations.clampedFraction(
                                newFraction, min: minFraction, max: maxFraction
                            )
                        }
                )
                .accessibilityLabel("Resize pinned image panel")
                .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }
}
