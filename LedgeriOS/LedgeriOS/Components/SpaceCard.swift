import SwiftUI

/// Space display card with hero image, name, item count, checklist progress, and optional notes.
struct SpaceCard: View {
    let space: Space
    let itemCount: Int
    var showNotes: Bool = true
    let onPress: () -> Void
    var onMenuPress: (() -> Void)?

    private var primaryImageUrl: String? {
        space.images?.first(where: { $0.isPrimary == true })?.url
            ?? space.images?.first?.url
    }

    private struct ChecklistRow: Identifiable {
        let id: String
        let name: String
        let checked: Int
        let total: Int
        var percentage: Double { total > 0 ? Double(checked) / Double(total) * 100 : 0 }
    }

    private var checklistRows: [ChecklistRow]? {
        guard let checklists = space.checklists, !checklists.isEmpty else { return nil }
        let rows = checklists
            .map { cl in
                ChecklistRow(
                    id: cl.id,
                    name: cl.name,
                    checked: cl.items.filter(\.isChecked).count,
                    total: cl.items.count
                )
            }
            .filter { $0.total > 0 }
        return rows.isEmpty ? nil : rows
    }

    var body: some View {
        ImageCard(imageUrl: primaryImageUrl, onPress: onPress) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(space.name.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "Untitled space" : space.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)
                        .lineLimit(2)

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
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                if let rows = checklistRows {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            VStack(spacing: 3) {
                                HStack {
                                    Text(row.name)
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textSecondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(row.checked)/\(row.total)")
                                        .font(Typography.caption)
                                        .foregroundStyle(BrandColors.textSecondary)
                                        .fixedSize()
                                }

                                ProgressBar(
                                    percentage: row.percentage,
                                    fillColor: Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255),
                                    height: 5
                                )
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                if showNotes, let notes = space.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 6)
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
