import SwiftUI

/// Wraps SpacePickerList in a titled bottom sheet for setting an item's space.
struct SetSpaceModal: View {
    let spaces: [Space]
    let currentSpaceId: String?
    let onSelect: (Space?) -> Void

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

            SpacePickerList(spaces: spaces, selectedId: currentSpaceId) { space in
                onSelect(space)
                dismiss()
            }
        }
    }
}

#Preview {
    SetSpaceModal(
        spaces: [Space(name: "Living Room"), Space(name: "Bedroom")],
        currentSpaceId: nil,
        onSelect: { _ in }
    )
}
