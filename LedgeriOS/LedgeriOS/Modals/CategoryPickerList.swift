import SwiftUI

/// Single-select budget category picker presented as a bottom sheet list.
struct CategoryPickerList: View {
    let categories: [BudgetCategory]
    let selectedId: String?
    let onSelect: (BudgetCategory?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var visibleCategories: [BudgetCategory] {
        categories
            .filter { $0.isArchived != true }
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Budget Category")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // "No Category" option
                    categoryRow(name: "No Category", isSelected: selectedId == nil) {
                        onSelect(nil)
                        dismiss()
                    }

                    ForEach(visibleCategories) { category in
                        categoryRow(
                            name: category.name,
                            isSelected: category.id == selectedId
                        ) {
                            onSelect(category)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(.top, Spacing.screenPadding)
    }

    @ViewBuilder
    private func categoryRow(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
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
    CategoryPickerList(
        categories: [
            BudgetCategory(name: "Furnishings"),
            BudgetCategory(name: "Lighting"),
            BudgetCategory(name: "Textiles"),
        ],
        selectedId: nil,
        onSelect: { _ in }
    )
}
