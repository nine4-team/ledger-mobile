import SwiftUI

/// Card with async image area and content below. Used by ProjectCard and SpaceCard.
struct ImageCard<Content: View>: View {
    let imageUrl: String?
    var thumbnailUrl: String?
    var aspectRatio: CGFloat = 3 / 1
    var onPress: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        let cardContent = VStack(spacing: 0) {
            imageArea
            content
                .padding(Spacing.cardPadding)
        }
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.borderSecondary, lineWidth: Dimensions.borderWidth)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)

        if let onPress {
            Button(action: onPress) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        if let imageUrl, !imageUrl.isEmpty {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    FirebaseImage(url: imageUrl, thumbnailUrl: thumbnailUrl, contentMode: .fill) {
                        placeholder
                            .overlay { ProgressView() }
                    }
                }
                .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(BrandColors.surfaceTertiary)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(Typography.h1)
                    .foregroundStyle(BrandColors.textTertiary)
            }
    }
}

#Preview("No Image (Placeholder)") {
    ImageCard(imageUrl: nil) {
        Text("Card Content")
            .font(Typography.body)
    }
    .padding(Spacing.screenPadding)
}

#Preview("With Image URL") {
    ImageCard(imageUrl: "https://picsum.photos/400/225") {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Project Name")
                .font(Typography.h3)
            Text("Some description here")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }
    .padding(Spacing.screenPadding)
}

#Preview("Invalid URL (Error)") {
    ImageCard(imageUrl: "not-a-url") {
        Text("Card with bad URL")
            .font(Typography.body)
    }
    .padding(Spacing.screenPadding)
}

#Preview("Tappable") {
    ImageCard(imageUrl: nil, onPress: {}) {
        Text("Tap me")
            .font(Typography.body)
    }
    .padding(Spacing.screenPadding)
}
