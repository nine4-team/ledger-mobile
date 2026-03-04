import SwiftUI

/// Grouped multi-select filter menu for transactions.
/// 8 filter groups matching the React Native app:
/// Status, Reimbursement Status, Email Receipt, Transaction Type,
/// Completeness, Budget Category, Purchased By, Source.
struct TransactionFilterMenu: View {
    @Binding var isPresented: Bool
    @Binding var filterState: TransactionFilterState
    var budgetCategories: [(id: String, name: String)] = []
    var sources: [String] = []

    var body: some View {
        EmptyView()
            .sheet(isPresented: $isPresented) {
                ActionMenuSheet(
                    title: "Filter",
                    items: buildMenuItems(),
                    closeOnItemPress: false
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Build Menu Items

    private func buildMenuItems() -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []

        items.append(filterGroup(
            id: "status",
            label: "Status",
            icon: "circle.fill",
            group: .status,
            options: [
                ("all", "All"),
                ("pending", "Pending"),
                ("completed", "Completed"),
                ("canceled", "Canceled"),
            ]
        ))

        items.append(filterGroup(
            id: "reimbursement",
            label: "Reimbursement Status",
            icon: "arrow.left.arrow.right",
            group: .reimbursementStatus,
            options: [
                ("all", "All"),
                ("we-owe", "Owed to Client"),
                ("client-owes", "Owed to Design Business"),
            ]
        ))

        items.append(filterGroup(
            id: "receipt",
            label: "Email Receipt",
            icon: "envelope",
            group: .emailReceipt,
            options: [
                ("all", "All"),
                ("yes", "Yes"),
                ("no", "No"),
            ]
        ))

        items.append(filterGroup(
            id: "type",
            label: "Transaction Type",
            icon: "tag",
            group: .transactionType,
            options: [
                ("all", "All"),
                ("purchase", "Purchase"),
                ("return", "Return"),
            ]
        ))

        items.append(filterGroup(
            id: "completeness",
            label: "Completeness",
            icon: "checkmark.circle",
            group: .completeness,
            options: [
                ("all", "All"),
                ("needs-review", "Needs Review"),
                ("complete", "Complete"),
            ]
        ))

        if !budgetCategories.isEmpty {
            var catOptions: [(String, String)] = [("all", "All")]
            catOptions.append(contentsOf: budgetCategories.map { ($0.id, $0.name) })
            items.append(filterGroup(
                id: "budget-category",
                label: "Budget Category",
                icon: "folder",
                group: .budgetCategory,
                options: catOptions
            ))
        }

        items.append(filterGroup(
            id: "purchased-by",
            label: "Purchased By",
            icon: "person",
            group: .purchasedBy,
            options: [
                ("all", "All"),
                ("client-card", "Client"),
                ("design-business", "Design Business"),
                ("missing", "Not Set"),
            ]
        ))

        if !sources.isEmpty {
            var srcOptions: [(String, String)] = [("all", "All")]
            srcOptions.append(contentsOf: sources.map { ($0, $0) })
            items.append(filterGroup(
                id: "source",
                label: "Source",
                icon: "building.2",
                group: .source,
                options: srcOptions
            ))
        }

        return items
    }

    private func filterGroup(
        id: String,
        label: String,
        icon: String,
        group: TransactionFilterState.FilterGroup,
        options: [(value: String, label: String)]
    ) -> ActionMenuItem {
        let activeSelections = filterState.selections(for: group)

        let subactions = options.map { (value, optLabel) in
            let isSelected: Bool
            if value == "all" {
                isSelected = activeSelections.isEmpty
            } else {
                isSelected = activeSelections.contains(value)
            }
            return ActionMenuSubitem(
                id: value,
                label: optLabel,
                icon: isSelected ? "checkmark.circle.fill" : "circle"
            ) {
                filterState.toggle(group: group, value: value)
            }
        }

        // Show the active sub-selection key if exactly one is selected
        let selectedKey: String? = activeSelections.count == 1 ? activeSelections.first : nil

        return ActionMenuItem(
            id: id,
            label: label,
            icon: icon,
            subactions: subactions,
            selectedSubactionKey: selectedKey
        )
    }
}

// MARK: - Previews

#Preview("Transaction Filter Menu") {
    @Previewable @State var show = true
    @Previewable @State var filters = TransactionFilterState()

    TransactionFilterMenu(
        isPresented: $show,
        filterState: $filters,
        budgetCategories: [
            (id: "cat-1", name: "Materials"),
            (id: "cat-2", name: "Labor"),
            (id: "cat-3", name: "Accessories"),
        ],
        sources: ["Amazon", "Wayfair", "Homegoods"]
    )
}
