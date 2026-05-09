import SwiftUI

/// Single-select picker filtered to return-type transactions that still need
/// review (isComplete != true). Used when linking an item to an in-progress
/// return transaction.
struct ReturnTransactionPickerModal: View {
    let transactions: [Transaction]
    var selectedId: String?
    let onSelect: (Transaction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// Only incomplete return-type transactions.
    private var returnTransactions: [Transaction] {
        transactions
            .filter { tx in
                let isReturn = tx.isReturnTransaction
                let isIncomplete = tx.isComplete != true
                let isNotCanceled = tx.status != .canceled
                return isReturn && isIncomplete && isNotCanceled
            }
            .filter { SearchCalculations.transactionPickerMatches(transaction: $0, query: searchText) }
            .sorted { a, b in
                let dateA = a.transactionDate ?? ""
                let dateB = b.transactionDate ?? ""
                return dateA > dateB
            }
    }

    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Link Return Transaction")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)

            SearchField(
                text: $searchText,
                placeholder: "Search source or amount"
            )
            .padding(.horizontal, Spacing.screenPadding)

            if returnTransactions.isEmpty {
                ContentUnavailableView(
                    hasSearchQuery ? "No matching returns" : "No pending returns",
                    systemImage: hasSearchQuery ? "magnifyingglass" : "arrow.uturn.left",
                    description: hasSearchQuery ? nil : Text("There are no incomplete return transactions in this project.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(returnTransactions) { transaction in
                            Button {
                                onSelect(transaction)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(transactionLabel(transaction))
                                            .font(Typography.body)
                                            .foregroundStyle(BrandColors.textPrimary)
                                        if let source = transaction.source, !source.isEmpty {
                                            Text(source)
                                                .font(Typography.small)
                                                .foregroundStyle(BrandColors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    if transaction.id == selectedId {
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
                    }
                }
            }
        }
    }

    private func transactionLabel(_ transaction: Transaction) -> String {
        if let date = transaction.transactionDate, !date.isEmpty {
            return "Return – \(date)"
        }
        if let amount = transaction.amountCents {
            return "Return – \(CurrencyFormatting.formatCentsWithDecimals(amount))"
        }
        return "Return Transaction"
    }
}
