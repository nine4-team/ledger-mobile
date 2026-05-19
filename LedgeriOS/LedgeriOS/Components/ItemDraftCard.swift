import SwiftUI

struct ItemDraftCard: View {
    let protoItem: ProtoItem

    private var photos: [AttachmentRef] {
        protoItem.photos ?? []
    }

    private var primaryPhoto: AttachmentRef? {
        photos.first(where: { $0.isPrimary == true }) ?? photos.first
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

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(
                    badges: [CardBadge(text: statusLabel, color: StatusColors.badgeNeedsReview)],
                    menuTitle: "Item Draft"
                )

                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        thumbnailView

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

                    if photos.count > 1 {
                        HStack(spacing: Spacing.xs) {
                            ForEach(Array(photos.prefix(4).enumerated()), id: \.offset) { _, photo in
                                photoThumb(photo, size: 52)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .findEntity(id: protoItem.id)
        .findMatchHighlight()
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let primaryPhoto {
            photoThumb(primaryPhoto, size: 108)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                    .fill(BrandColors.surfaceTertiary)
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .frame(width: 108, height: 108)
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.thumbnailRadius)
                    .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
            )
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
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
        )
    }
}
