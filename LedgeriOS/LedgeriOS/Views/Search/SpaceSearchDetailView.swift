import SwiftUI

/// Minimal space detail view for search result navigation.
/// Will be replaced by a full SpaceDetailView when the spaces feature is built.
struct SpaceSearchDetailView: View {
    let space: Space

    @Environment(AccountContext.self) private var accountContext

    private var spaceItems: [Item] {
        guard let spaceId = space.id else { return [] }
        return accountContext.allItems.filter { $0.spaceId == spaceId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Notes
                if let notes = space.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Notes")
                            .sectionLabelStyle()
                        Text(notes)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
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
                                Text(checklist.name)
                                    .font(Typography.h3)
                                    .foregroundStyle(BrandColors.textPrimary)
                                ForEach(checklist.items) { item in
                                    HStack(spacing: Spacing.sm) {
                                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isChecked ? BrandColors.primary : BrandColors.textTertiary)
                                        Text(item.text)
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
        .background(BrandColors.background)
        .navigationTitle(space.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SpaceSearchDetailView(
            space: Space(
                name: "Living Room",
                notes: "Main living area with hardwood floors",
                checklists: [
                    Checklist(name: "Fixtures", items: [
                        ChecklistItem(text: "Ceiling fan", isChecked: true),
                        ChecklistItem(text: "Light switch", isChecked: false),
                    ])
                ]
            )
        )
    }
    .environment(AccountContext(
        accountsService: AccountsService(syncTracker: NoOpSyncTracker()),
        membersService: AccountMembersService(syncTracker: NoOpSyncTracker())
    ))
}
