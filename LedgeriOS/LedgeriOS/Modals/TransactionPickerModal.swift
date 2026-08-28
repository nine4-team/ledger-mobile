import SwiftUI

/// Single-select picker for all project transactions.
struct TransactionPickerModal: View {
    let transactions: [Transaction]
    var selectedId: String?
    let onSelect: (Transaction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var visibleTransactions: [Transaction] {
        transactions
            .filter { $0.status != .canceled }
            .filter { SearchCalculations.transactionPickerMatches(transaction: $0, query: searchText) }
            .sorted { a, b in
                let dateA = a.transactionDate ?? ""
                let dateB = b.transactionDate ?? ""
                return dateA > dateB
            }
    }

    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Link Transaction")
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

            SearchField(
                text: $searchText,
                placeholder: "Search ID, source, or amount"
            )
            .padding(.horizontal, Spacing.screenPadding)

            if visibleTransactions.isEmpty {
                ContentUnavailableView(
                    hasSearchQuery ? "No matching transactions" : "No transactions",
                    systemImage: hasSearchQuery ? "magnifyingglass" : "arrow.left.arrow.right"
                )
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // "No transaction" option
                        if !hasSearchQuery {
                            transactionRow(
                                label: "No Transaction",
                                sublabel: nil,
                                isSelected: selectedId == nil
                            ) {
                                dismiss()
                            }
                        }

                        ForEach(visibleTransactions) { transaction in
                            transactionRow(
                                label: transactionLabel(transaction),
                                sublabel: transactionSublabel(transaction),
                                isSelected: transaction.id == selectedId
                            ) {
                                onSelect(transaction)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transactionRow(
        label: String,
        sublabel: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(label)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let sub = sublabel, !sub.isEmpty {
                        Text(sub)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
                Spacer()
                if isSelected {
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

        Divider()
            .padding(.horizontal, Spacing.screenPadding)
    }

    private func transactionLabel(_ transaction: Transaction) -> String {
        let type = transaction.transactionType?.displayLabel ?? "Transaction"
        if let date = transaction.transactionDate, !date.isEmpty {
            return "\(type) – \(date)"
        }
        return type
    }

    private func transactionSublabel(_ transaction: Transaction) -> String? {
        let vendor = transaction.source
        let amount = transaction.amountCents.map { CurrencyFormatting.formatCentsWithDecimals($0) }
        let matchingID = SearchCalculations.matchingTransactionID(
            transaction: transaction,
            query: searchText
        )

        var components: [String] = []
        if let vendor, !vendor.isEmpty { components.append(vendor) }
        if let amount { components.append(amount) }
        if let matchingID { components.append("ID: \(matchingID)") }

        return components.isEmpty ? nil : components.joined(separator: " · ")
    }
}
