import SwiftUI

struct ItemDraftCard: View {
    let protoItem: ProtoItem
    var onOpen: () -> Void
    var onConvert: () -> Void
    var onMerge: () -> Void
    var toastMessage: String?
    var onToggleFromInventory: (() -> Void)?
    var onDelete: () -> Void

    @State private var showMenu = false
    @State private var menuPendingAction: (() -> Void)?

    private let thumbnailSize: CGFloat = 88

    private var photos: [AttachmentRef] {
        protoItem.photos ?? []
    }

    private var previewPhotos: [AttachmentRef] {
        let ordered = photos.sorted { first, second in
            (first.isPrimary == true ? 0 : 1) < (second.isPrimary == true ? 0 : 1)
        }
        return Array(ordered.prefix(3))
    }

    private var isFromInventory: Bool {
        protoItem.sourceHint == .fromInventory
    }

    private var showsFromInventoryControl: Bool {
        protoItem.projectId != nil && onToggleFromInventory != nil
    }

    var body: some View {
        Card(padding: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Button(action: onOpen) {
                    photoStrip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)

                actionColumn
            }
        }
        .overlay(alignment: .topTrailing) {
            if let toastMessage {
                ToastBanner(message: toastMessage)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .offset(x: -48, y: 52)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: toastMessage)
        .findEntity(id: protoItem.id)
        .findMatchHighlight()
        .adaptivePresentation(isPresented: $showMenu, style: .quickMenu, onDismiss: {
            menuPendingAction?()
            menuPendingAction = nil
        }) {
            ActionMenuSheet(
                title: "Item Quick Draft",
                items: [
                    ActionMenuItem(id: "convert", label: "Convert to Item", icon: "square.and.arrow.down", onPress: onConvert),
                    ActionMenuItem(id: "merge", label: "Merge with Existing Item", icon: "arrow.triangle.merge", onPress: onMerge),
                    ActionMenuItem(id: "delete", label: "Delete Draft", icon: "trash", isDestructive: true, onPress: onDelete),
                ],
                onSelectAction: { action in
                    menuPendingAction = action
                }
            )
        }
    }

    private var actionColumn: some View {
        VStack(spacing: 0) {
            Button {
                showMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandColors.textSecondary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 44, height: showsFromInventoryControl ? 44 : thumbnailSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsFromInventoryControl {
                fromInventoryControl
            }
        }
        .frame(width: 44, height: thumbnailSize)
    }

    private var fromInventoryControl: some View {
        Button {
            onToggleFromInventory?()
        } label: {
            Image(systemName: isFromInventory ? "shippingbox.fill" : "shippingbox")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isFromInventory ? BrandColors.primary : BrandColors.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                        .fill(isFromInventory ? BrandColors.primary.opacity(0.12) : BrandColors.surfaceTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                        .stroke(isFromInventory ? BrandColors.primary.opacity(0.35) : BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
                )
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .accessibilityLabel(isFromInventory ? "Marked from inventory" : "Mark from inventory")
    }

    @ViewBuilder
    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if previewPhotos.isEmpty {
                HStack(spacing: Spacing.sm) {
                    placeholderThumb
                    Spacer(minLength: 0)
                }
            } else {
                GeometryReader { proxy in
                    let visibleCount = visibleThumbnailCount(for: proxy.size.width)
                    HStack(spacing: Spacing.sm) {
                        ForEach(Array(previewPhotos.prefix(visibleCount).enumerated()), id: \.offset) { _, photo in
                            photoThumb(photo)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: thumbnailSize)
            }

            if let sku = protoItem.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty {
                FindableText("SKU: \(sku)")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func visibleThumbnailCount(for availableWidth: CGFloat) -> Int {
        let itemWidth = thumbnailSize + Spacing.sm
        let fitCount = Int((availableWidth + Spacing.sm) / itemWidth)
        return min(previewPhotos.count, max(1, fitCount))
    }

    private func photoThumb(_ photo: AttachmentRef) -> some View {
        FirebaseImage(url: photo.url, thumbnailUrl: photo.thumbnailUrlSm, contentMode: .fill) {
            ProgressView()
                .frame(width: thumbnailSize, height: thumbnailSize)
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
        .background(BrandColors.surfaceTertiary, in: RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(photo.isPrimary == true ? BrandColors.primary : BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }

    private var placeholderThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: "camera")
                .font(.system(size: 22))
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }
}

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Typography.small)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                Capsule()
                    .fill(BrandColors.primary)
            )
            .shadow(color: BrandColors.primary.opacity(0.25), radius: 10, y: 4)
            .accessibilityLabel(message)
    }
}

extension View {
    func toastMessage(_ message: String?) -> some View {
        overlay(alignment: .bottom) {
            if let message {
                ToastBanner(message: message)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: message)
    }
}
