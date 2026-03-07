import SwiftUI

/// Shared card header row with selector, badges, bookmark, and kebab menu.
/// Owns the menu sheet presentation state, eliminating duplication across cards.
struct CardHeader: View {
    // Selection
    var isSelected: Binding<Bool>?
    var selectionLabel: String = ""

    // Badges
    var badges: [CardBadge] = []

    // Actions
    var bookmarked: Bool = false
    var onBookmarkPress: (() -> Void)?
    var warningMessage: String?
    var menuTitle: String = ""
    var menuItems: [ActionMenuItem] = []

    @State private var showMenu = false
    @State private var menuPendingAction: (() -> Void)?

    private var showSelector: Bool {
        isSelected != nil
    }

    private var hasContent: Bool {
        showSelector || !badges.isEmpty || !(warningMessage?.isEmpty ?? true) || onBookmarkPress != nil || !menuItems.isEmpty
    }

    @ViewBuilder
    var body: some View {
        if hasContent {
            HStack(spacing: Spacing.sm) {
                if showSelector, let binding = isSelected {
                    CardSelectorButton(
                        isSelected: binding.wrappedValue,
                        label: selectionLabel,
                        action: { binding.wrappedValue.toggle() }
                    )
                }

                Spacer(minLength: 0)

                if !badges.isEmpty {
                    badgeRow
                }

                headerActions
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .overlay(alignment: .bottom) {
                CardDivider()
            }
            .sheet(isPresented: $showMenu) {
                ActionMenuSheet(
                    title: menuTitle,
                    items: menuItems,
                    onSelectAction: { action in
                        menuPendingAction = action
                    }
                )
                .sheetStyle(.selectionMenu)
            }
            .onChange(of: showMenu) { _, isShowing in
                if !isShowing, let action = menuPendingAction {
                    menuPendingAction = nil
                    action()
                }
            }
        }
    }

    // MARK: - Badge Row

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                Badge(
                    text: badge.text,
                    color: badge.color,
                    backgroundOpacity: badge.backgroundOpacity,
                    borderOpacity: badge.borderOpacity
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Header Actions

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: Spacing.sm) {
            if let warningMessage, !warningMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(StatusColors.badgeWarning)
                    .font(.system(size: 18))
            }

            if let onBookmarkPress {
                CardBookmarkButton(
                    isBookmarked: bookmarked,
                    action: onBookmarkPress
                )
            }

            if !menuItems.isEmpty {
                CardKebabButton {
                    showMenu = true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Full Header") {
    VStack {
        CardHeader(
            isSelected: .constant(false),
            selectionLabel: "Test Item",
            badges: [
                CardBadge(text: "Purchase", color: BrandColors.primary),
                CardBadge(text: "Furnishings", color: BrandColors.primary),
            ],
            bookmarked: true,
            onBookmarkPress: {},
            menuTitle: "Test",
            menuItems: [
                ActionMenuItem(id: "edit", label: "Edit", icon: "pencil"),
            ]
        )

        CardHeader(
            badges: [
                CardBadge(text: "Needs Review", color: StatusColors.badgeNeedsReview, backgroundOpacity: 0.08),
            ],
            menuTitle: "Options",
            menuItems: [
                ActionMenuItem(id: "delete", label: "Delete", icon: "trash", isDestructive: true),
            ]
        )
    }
    .preferredColorScheme(.dark)
}
