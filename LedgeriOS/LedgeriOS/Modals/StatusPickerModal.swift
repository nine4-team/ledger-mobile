import SwiftUI

/// Single-select status picker for item status updates.
/// Excludes `.sold` — that status is system-set by sale operations.
struct StatusPickerModal: View {
    var currentStatus: ItemStatus?
    let onSelect: (ItemStatus) -> Void

    @Environment(\.dismiss) private var dismiss

    /// User-settable statuses (excludes `.sold` — system-set only).
    private let statuses: [(status: ItemStatus, icon: String)] = [
        (.toPurchase, "cart"),
        (.purchased, "checkmark.circle"),
        (.toReturn, "arrow.uturn.left"),
        (.returned, "arrow.uturn.left.circle.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Change Status")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(statuses, id: \.status) { option in
                        Button {
                            onSelect(option.status)
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(BrandColors.primary)
                                    .frame(width: 28)

                                Text(option.status.displayLabel)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Spacer()

                                if option.status == currentStatus {
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

                        if option.status != statuses.last?.status {
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
    StatusPickerModal(currentStatus: .purchased, onSelect: { _ in })
}
