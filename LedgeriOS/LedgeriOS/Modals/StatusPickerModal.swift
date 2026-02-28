import SwiftUI

/// Single-select status picker for item status updates.
/// Options: to-purchase, purchased, to-return, returned.
struct StatusPickerModal: View {
    var currentStatus: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let statuses: [(id: String, label: String, icon: String)] = [
        ("to-purchase", "To Purchase", "cart"),
        ("purchased", "Purchased", "checkmark.circle"),
        ("to return", "To Return", "arrow.uturn.left"),
        ("returned", "Returned", "arrow.uturn.left.circle.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Change Status")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(statuses, id: \.id) { option in
                        Button {
                            onSelect(option.id)
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(BrandColors.primary)
                                    .frame(width: 28)

                                Text(option.label)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Spacer()

                                if option.id == currentStatus {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(BrandColors.primary)
                                }
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option.id != statuses.last?.id {
                            Divider()
                                .padding(.horizontal, Spacing.screenPadding)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    StatusPickerModal(currentStatus: "purchased", onSelect: { _ in })
}
