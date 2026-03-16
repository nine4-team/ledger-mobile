import SwiftUI

/// Space display card with hero image, name, item count, checklist progress, and optional notes.
struct SpaceCard: View {
    let space: Space
    let itemCount: Int
    var onPress: (() -> Void)? = nil
    var onMenuPress: (() -> Void)?

    private var primaryImage: AttachmentRef? {
        space.images?.first(where: { $0.isPrimary == true })
            ?? space.images?.first
    }

    private var checklistProgress: (text: String, percentage: Double)? {
        guard let checklists = space.checklists, !checklists.isEmpty else { return nil }
        let allItems = checklists.flatMap(\.items)
        guard !allItems.isEmpty else { return nil }
        let done = allItems.filter(\.isChecked).count
        let pct = Double(done) / Double(allItems.count) * 100
        return ("Checklists: \(done)/\(allItems.count) items done", pct)
    }

    var body: some View {
        ImageCard(imageUrl: primaryImage?.url, thumbnailUrl: primaryImage?.thumbnailUrlMd, onPress: onPress) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(space.name.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Untitled space" : space.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    if let onMenuPress {
                        CardKebabButton(action: onMenuPress)
                    }
                }

                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                if let progress = checklistProgress {
                    HStack(spacing: Spacing.sm) {
                        Text(progress.text)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .fixedSize()

                        ProgressBar(
                            percentage: progress.percentage,
                            fillColor: BrandColors.primary,
                            height: 5
                        )
                    }
                } else {
                    Text("")
                        .font(Typography.caption)
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
                ]),
                Checklist(name: "Finishes", items: [
                    ChecklistItem(text: "Tile", isChecked: true),
                    ChecklistItem(text: "Paint", isChecked: false),
                    ChecklistItem(text: "Grout", isChecked: false),
                    ChecklistItem(text: "Trim", isChecked: false),
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
