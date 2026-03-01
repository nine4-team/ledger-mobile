import SwiftUI

/// Space display card with hero image, name, item count, checklist progress, and optional notes.
struct SpaceCard: View {
    let space: Space
    let itemCount: Int
    var showNotes: Bool = false
    let onPress: () -> Void
    var onMenuPress: (() -> Void)?

    private var primaryImageUrl: String? {
        space.images?.first(where: { $0.isPrimary == true })?.url
            ?? space.images?.first?.url
    }

    private var checklistCounts: (checked: Int, total: Int)? {
        guard let checklists = space.checklists, !checklists.isEmpty else { return nil }
        let totalItems = checklists.reduce(0) { $0 + $1.items.count }
        guard totalItems > 0 else { return nil }
        let checkedItems = checklists.reduce(0) { sum, checklist in
            sum + checklist.items.filter(\.isChecked).count
        }
        return (checkedItems, totalItems)
    }

    private var checklistProgress: Double? {
        guard let counts = checklistCounts else { return nil }
        return Double(counts.checked) / Double(counts.total) * 100
    }

    var body: some View {
        ImageCard(imageUrl: primaryImageUrl, onPress: onPress) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(space.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if let onMenuPress {
                        Button(action: onMenuPress) {
                            Image(systemName: "ellipsis")
                                .font(Typography.body)
                                .foregroundStyle(BrandColors.textSecondary)
                                .padding(Spacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                if let progress = checklistProgress, let counts = checklistCounts {
                    HStack(spacing: Spacing.sm) {
                        ProgressBar(
                            percentage: progress,
                            fillColor: BrandColors.primary,
                            height: 4
                        )

                        Text("\(counts.checked)/\(counts.total)")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                            .fixedSize()
                    }
                }

                if showNotes, let notes = space.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

#Preview("Basic Space") {
    SpaceCard(
        space: Space(name: "Living Room"),
        itemCount: 5,
        onPress: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Space with Menu") {
    SpaceCard(
        space: Space(name: "Kitchen", notes: "Need to finalize countertop material selection before ordering cabinets."),
        itemCount: 12,
        showNotes: true,
        onPress: {},
        onMenuPress: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Space with Checklists") {
    SpaceCard(
        space: Space(
            name: "Master Bathroom",
            checklists: [
                Checklist(name: "Fixtures", items: [
                    ChecklistItem(text: "Shower head", isChecked: true),
                    ChecklistItem(text: "Faucet", isChecked: true),
                    ChecklistItem(text: "Toilet", isChecked: false),
                ])
            ]
        ),
        itemCount: 3,
        onPress: {}
    )
    .padding(Spacing.screenPadding)
}

#Preview("Space with Image") {
    SpaceCard(
        space: Space(
            name: "Garage",
            images: [AttachmentRef(url: "https://picsum.photos/400/225", isPrimary: true)]
        ),
        itemCount: 8,
        onPress: {}
    )
    .padding(Spacing.screenPadding)
}
