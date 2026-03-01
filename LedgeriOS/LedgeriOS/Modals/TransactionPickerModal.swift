import SwiftUI

/// Single-select picker for all project transactions.
struct TransactionPickerModal: View {
    let transactions: [Transaction]
    var selectedId: String?
    let onSelect: (Transaction) -> Void

    @Environment(\.dismiss) private var dismiss

    private var visibleTransactions: [Transaction] {
        transactions
            .filter { $0.isCanceled != true }
            .sorted { a, b in
                let dateA = a.transactionDate ?? ""
                let dateB = b.transactionDate ?? ""
                return dateA > dateB
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Link Transaction")
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.screenPadding)

            if visibleTransactions.isEmpty {
                ContentUnavailableView("No transactions", systemImage: "arrow.left.arrow.right")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // "No transaction" option
                        transactionRow(
                            label: "No Transaction",
                            sublabel: nil,
                            isSelected: selectedId == nil
                        ) {
                            dismiss()
                        }

                        ForEach(visibleTransactions) { transaction in
                            transactionRow(
                                label: transactionLabel(transaction),
                                sublabel: transaction.source,
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
        let type = transaction.transactionType?.capitalized ?? "Transaction"
        if let date = transaction.transactionDate, !date.isEmpty {
            return "\(type) – \(date)"
        }
        if let amount = transaction.amountCents {
            return "\(type) – \(CurrencyFormatting.formatCentsWithDecimals(amount))"
        }
        return type
    }
}
