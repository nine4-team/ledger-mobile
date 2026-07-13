import SwiftUI

/// Minimal space detail view for search result navigation.
/// Will be replaced by a full SpaceDetailView when the spaces feature is built.
struct SpaceSearchDetailView: View {
    let route: SpaceRoute

    @Environment(AccountContext.self) private var accountContext

    private var space: Space? {
        NavigationRouteResolution.space(
            id: route.id,
            projectSpaces: [],
            accountSpaces: accountContext.allSpaces
        )
    }

    private var spaceItems: [Item] {
        accountContext.allItems.filter { $0.spaceId == route.id }
    }

    var body: some View {
        Group {
            if let space {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Notes
                        if let notes = space.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Notes")
                                    .sectionLabelStyle()
                                SelectableNoteText(text: notes, style: .body)
                            }
                        }

                        // Items count
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Items")
                                .sectionLabelStyle()
                            Text("\(spaceItems.count) item\(spaceItems.count == 1 ? "" : "s") in this space")
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textSecondary)
                        }

                        // Checklists
                        if let checklists = space.checklists, !checklists.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("Checklists")
                                    .sectionLabelStyle()
                                ForEach(checklists) { checklist in
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        FindableText(checklist.name)
                                            .font(Typography.h3)
                                            .foregroundStyle(BrandColors.textPrimary)
                                        ForEach(checklist.items) { item in
                                            HStack(spacing: Spacing.sm) {
                                                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(item.isChecked ? BrandColors.primary : BrandColors.textTertiary)
                                                FindableText(item.text)
                                                    .font(Typography.body)
                                                    .foregroundStyle(BrandColors.textPrimary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(Spacing.screenPadding)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BrandColors.background)
        .navigationTitle(space?.name ?? "Space")
        .navBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SpaceSearchDetailView(
            route: SpaceRoute(id: "space-1", projectId: "project-1")
        )
    }
    .environment(AccountContext(
        accountsService: AccountsService(),
        membersService: AccountMembersService()
    ))
}
