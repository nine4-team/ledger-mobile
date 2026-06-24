import SwiftUI

/// Picker sheet for selecting an item destination — either Business Inventory
/// or a specific project. Used in item creation to scope the item's Firestore path.
struct DestinationPickerSheet: View {
    /// Called when the user makes a selection. Passes the resolved context and
    /// the selected Project (nil for Business Inventory).
    let onSelect: (ItemCreationContext, Project?) -> Void

    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    private var projects: [Project] {
        accountContext.allProjects
            .filter { $0.isArchived != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Destination")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)

            ScrollView {
                LazyVStack(spacing: 0) {
                    destinationRow(
                        label: "Business Inventory",
                        sublabel: nil,
                        icon: "building.2"
                    ) {
                        onSelect(.inventory, nil)
                        dismiss()
                    }

                    ForEach(projects) { project in
                        destinationRow(
                            label: project.name.isEmpty ? "(unnamed)" : project.name,
                            sublabel: project.clientName.isEmpty ? nil : project.clientName,
                            icon: "folder"
                        ) {
                            guard let id = project.id else { return }
                            onSelect(.project(id, spaceId: nil), project)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destinationRow(
        label: String,
        sublabel: String?,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(label)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let sub = sublabel {
                        Text(sub)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
            .padding(.horizontal, Spacing.screenPadding)
    }
}
