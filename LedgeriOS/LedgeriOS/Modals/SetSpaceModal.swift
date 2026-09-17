import SwiftUI

/// Wraps SpacePickerList in a titled bottom sheet for setting an item's space.
#if canImport(FirebaseFirestore)
struct SetSpaceModal: View {
    let spaces: [Space]
    let currentSpaceId: String?
    let onSelect: (Space?) -> Void

    var body: some View {
        SetSpacePresentation(spaces: spaces.filter { $0.isArchived != true }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }, currentSpaceId: currentSpaceId, name: { $0.name }, onSelect: onSelect)
    }
}
#endif

struct SetSpacePresentation<SpaceValue: Identifiable>: View {
    let spaces: [SpaceValue]
    let currentSpaceId: SpaceValue.ID?
    let name: (SpaceValue) -> String
    var dismissOnSelect = true
    let onSelect: (SpaceValue?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Set Space")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)

            SpacePickerPresentation(spaces: spaces, selectedId: currentSpaceId,
                                    name: name, dismissOnSelect: dismissOnSelect) { space in
                onSelect(space)
            }
        }
    }
}

#if canImport(FirebaseFirestore)
#Preview {
    SetSpaceModal(
        spaces: [Space(name: "Living Room"), Space(name: "Bedroom")],
        currentSpaceId: nil,
        onSelect: { _ in }
    )
}
#endif
