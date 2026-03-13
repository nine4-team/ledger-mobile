import SwiftUI

// MARK: - Kebab Menu Button

/// Standard vertical ellipsis button for card headers.
/// Source of truth: TransactionCard's kebab pattern.
struct CardKebabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 18))
                .foregroundStyle(BrandColors.textSecondary)
                .rotationEffect(.degrees(90))
                .padding(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("More options")
    }
}

// MARK: - Bookmark Button

/// Standard bookmark toggle button for card headers.
struct CardBookmarkButton: View {
    let isBookmarked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18))
                .foregroundStyle(isBookmarked ? StatusColors.badgeError : BrandColors.primary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Add bookmark")
    }
}

// MARK: - Selector Button

/// Standard selection circle button for card headers.
/// Wraps SelectorCircle with proper Button, tap target, and accessibility.
struct CardSelectorButton: View {
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SelectorCircle(isSelected: isSelected, indicator: .dot)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Select \(label)")
    }
}

// MARK: - Previews

#Preview("Kebab Button") {
    CardKebabButton {}
}

#Preview("Bookmark States") {
    HStack(spacing: 24) {
        CardBookmarkButton(isBookmarked: false) {}
        CardBookmarkButton(isBookmarked: true) {}
    }
}

#Preview("Selector States") {
    HStack(spacing: 24) {
        CardSelectorButton(isSelected: false, label: "Item") {}
        CardSelectorButton(isSelected: true, label: "Item") {}
    }
}
