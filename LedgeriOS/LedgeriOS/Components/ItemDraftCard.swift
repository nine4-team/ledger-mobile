import SwiftUI

struct ItemDraftCard: View {
    let protoItem: ProtoItem

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var photos: [AttachmentRef] {
        protoItem.photos ?? []
    }

    private var sourceLabel: String {
        switch protoItem.sourceHint {
        case .purchasedByClient: return "Client Purchase"
        case .purchasedByBusiness: return "Business Purchase"
        case .fromInventory: return "From Inventory"
        case .unknown, nil: return "Source Not Sure"
        }
    }

    private var statusLabel: String {
        (protoItem.status ?? .open).displayLabel
    }

    private var createdLabel: String? {
        guard let createdAt = protoItem.createdAt else { return nil }
        return TransactionCardCalculations.formattedCreatedDate(createdAt)
    }

    private var previewPhotos: [AttachmentRef] {
        let ordered = photos.sorted { first, second in
            (first.isPrimary == true ? 0 : 1) < (second.isPrimary == true ? 0 : 1)
        }
        return Array(ordered.prefix(3))
    }

    private var thumbnailSize: CGFloat {
        horizontalSizeClass == .compact ? 76 : 92
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    badges: [CardBadge(text: statusLabel, color: StatusColors.badgeNeedsReview)],
                    menuTitle: "Item Draft"
                )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    photoStrip

                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Item Draft")
                                .font(Typography.h3)
                                .foregroundStyle(BrandColors.textPrimary)

                            Text(sourceLabel)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)

                            if let createdLabel {
                                Text(createdLabel)
                                    .font(Typography.small)
                                    .foregroundStyle(BrandColors.textSecondary)
                            }

                            if let notes = protoItem.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(Typography.small)
                                    .foregroundStyle(BrandColors.textSecondary)
                                    .lineLimit(3)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .findEntity(id: protoItem.id)
        .findMatchHighlight()
    }

    @ViewBuilder
    private var photoStrip: some View {
        if previewPhotos.isEmpty {
            placeholderThumb(size: thumbnailSize)
        } else {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(previewPhotos.enumerated()), id: \.offset) { _, photo in
                    photoThumb(photo, size: thumbnailSize)
                }
            }
        }
    }

    private func photoThumb(_ photo: AttachmentRef, size: CGFloat) -> some View {
        FirebaseImage(url: photo.url, thumbnailUrl: photo.thumbnailUrlSm, contentMode: .fill) {
            ProgressView()
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
        .background(BrandColors.surfaceTertiary, in: RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(photo.isPrimary == true ? BrandColors.primary : BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }

    private func placeholderThumb(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .fill(BrandColors.surfaceTertiary)
            Image(systemName: "camera")
                .font(.system(size: 22))
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }
}
