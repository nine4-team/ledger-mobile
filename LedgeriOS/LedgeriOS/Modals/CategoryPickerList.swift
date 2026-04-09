import SwiftUI

/// Single-select budget category picker presented as a bottom sheet list.
struct CategoryPickerList: View {
    let categories: [BudgetCategory]
    let selectedId: String?
    let onSelect: (BudgetCategory?) -> Void
    /// When true (default), the picker dismisses itself after a selection —
    /// appropriate when presented as its own sheet. Set to `false` when
    /// embedded inline inside another modal, where dismissing would tear
    /// down the parent sheet.
    var autoDismissOnSelect: Bool = true

    @Environment(\.dismiss) private var dismiss

    private var visibleCategories: [BudgetCategory] {
        categories
            .filter { $0.isArchived != true }
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Budget Category")
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
            .padding(.bottom, Spacing.md)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // "No Category" option
                    categoryRow(name: "No Category", isSelected: selectedId == nil) {
                        onSelect(nil)
                        if autoDismissOnSelect { dismiss() }
                    }

                    ForEach(visibleCategories) { category in
                        categoryRow(
                            name: category.name,
                            isSelected: category.id == selectedId
                        ) {
                            onSelect(category)
                            if autoDismissOnSelect { dismiss() }
                        }
                    }
                }
            }
        }
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
