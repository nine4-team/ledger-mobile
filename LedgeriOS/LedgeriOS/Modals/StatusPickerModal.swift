import SwiftUI

/// Backend-independent rows shared by the original and target status pickers.
struct ItemStatusPickerRows: View {
    struct Option: Identifiable {
        let id: String
        let label: String
        let icon: String
    }
    let options: [Option]
    let currentID: String?
    let onSelect: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(options) { option in
                Button { onSelect(option.id) } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: option.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(BrandColors.primary)
                            .frame(width: 28)
                        Text(option.label)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        if option.id == currentID {
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
                .accessibilityValue(option.id == currentID ? "Selected" : "Not selected")
                if option.id != options.last?.id {
                    Divider().padding(.horizontal, Spacing.screenPadding)
                }
            }
        }
    }
}

#if canImport(FirebaseFirestore)
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
                ItemStatusPickerRows(options: statuses.map {
                    .init(id: $0.status.rawValue, label: $0.status.displayLabel, icon: $0.icon)
                }, currentID: currentStatus?.rawValue) { raw in
                    guard let selected = ItemStatus(rawValue: raw) else { return }
                    onSelect(selected)
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    StatusPickerModal(currentStatus: .purchased, onSelect: { _ in })
}
#endif
