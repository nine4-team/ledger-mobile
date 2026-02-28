import SwiftUI

/// Single-select space picker list.
/// Shows project spaces, a "No Space" option, and optionally a "Create New Space" row.
struct SpacePickerList: View {
    let spaces: [Space]
    var selectedId: String? = nil
    let onSelect: (Space?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var visibleSpaces: [Space] {
        spaces
            .filter { $0.isArchived != true }
            .sorted { ($0.name).localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Set Space")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // "No Space" option
                    spaceRow(name: "No Space", icon: "xmark.circle", isSelected: selectedId == nil) {
                        onSelect(nil)
                        dismiss()
                    }

                    ForEach(visibleSpaces) { space in
                        spaceRow(
                            name: space.name,
                            icon: "mappin.and.ellipse",
                            isSelected: space.id == selectedId
                        ) {
                            onSelect(space)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(.top, Spacing.screenPadding)
    }

    @ViewBuilder
    private func spaceRow(name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 24)

                Text(name)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BrandColors.primary)
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SpacePickerList(
        spaces: [Space(name: "Living Room"), Space(name: "Primary Bedroom"), Space(name: "Kitchen")],
        selectedId: nil,
        onSelect: { _ in }
    )
}
