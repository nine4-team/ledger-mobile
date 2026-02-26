import SwiftUI

/// Card with async image area and content below. Used by ProjectCard and SpaceCard.
struct ImageCard<Content: View>: View {
    let imageUrl: String?
    var aspectRatio: CGFloat = 16 / 9
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
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )

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
        if let imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                        .overlay { ProgressView() }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspectRatio, contentMode: .fit)
                        .clipped()
                case .failure:
                    placeholder
                        .overlay {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Typography.h2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                @unknown default:
                    placeholder
                }
            }
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
