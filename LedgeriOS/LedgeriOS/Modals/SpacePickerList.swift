import SwiftUI

/// Single-select space picker list.
/// Shows project spaces, a "No Space" option, and optionally a "Create New Space" row.
#if canImport(FirebaseFirestore)
struct SpacePickerList: View {
    let spaces: [Space]
    var selectedId: String? = nil
    let onSelect: (Space?) -> Void

    private var visibleSpaces: [Space] {
        spaces
            .filter { $0.isArchived != true }
            .sorted { ($0.name).localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SpacePickerPresentation(spaces: visibleSpaces, selectedId: selectedId,
                                name: { $0.name }, onSelect: onSelect)
    }
}
#endif

/// Existing rows and selection marks with caller-owned, scoped data. A target
/// writer can keep the sheet open until local acceptance instead of dismissing
/// before an asynchronous save has succeeded.
struct SpacePickerPresentation<SpaceValue: Identifiable>: View {
    let spaces: [SpaceValue]
    var selectedId: SpaceValue.ID? = nil
    let name: (SpaceValue) -> String
    var dismissOnSelect = true
    let onSelect: (SpaceValue?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // "No Space" option
                    spaceRow(name: "No Space", icon: "xmark.circle", isSelected: selectedId == nil) {
                        onSelect(nil)
                        if dismissOnSelect { dismiss() }
                    }

                    ForEach(spaces) { space in
                        spaceRow(
                            name: name(space),
                            icon: "mappin.and.ellipse",
                            isSelected: space.id == selectedId
                        ) {
                            onSelect(space)
                            if dismissOnSelect { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle("Set Space")
            .navBarTitleDisplayMode(.inline)
        }
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

#if canImport(FirebaseFirestore)
#Preview {
    SpacePickerList(
        spaces: [Space(name: "Living Room"), Space(name: "Primary Bedroom"), Space(name: "Kitchen")],
        selectedId: nil,
        onSelect: { _ in }
    )
}
#endif
