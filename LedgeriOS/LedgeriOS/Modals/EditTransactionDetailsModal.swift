import SwiftUI

/// Bottom sheet for editing all transaction detail fields in the correct order (FR-5.6).
/// Field order: Vendor/Source → Amount → Date → Status → Purchased By →
/// Transaction Type → Reimbursement Type → Budget Category → Email Receipt →
/// (conditional) Subtotal → Tax Rate.
struct EditTransactionDetailsModal: View {
    let transaction: Transaction
    let budgetCategories: [BudgetCategory]
    let onSave: ([String: Any]) -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable state — initialized from transaction
    @State private var source: String
    @State private var amountText: String
    @State private var transactionDate: Date
    @State private var status: String
    @State private var purchasedBy: String
    @State private var transactionType: String
    @State private var reimbursementType: String
    @State private var budgetCategoryId: String?
    @State private var hasEmailReceipt: Bool
    @State private var subtotalText: String
    @State private var taxRateText: String

    // Sheet presentation
    @State private var showCategoryPicker = false

    init(transaction: Transaction, budgetCategories: [BudgetCategory], onSave: @escaping ([String: Any]) -> Void) {
        self.transaction = transaction
        self.budgetCategories = budgetCategories
        self.onSave = onSave

        _source = State(initialValue: transaction.source ?? "")
        _amountText = State(initialValue: Self.centsToText(transaction.amountCents))
        _transactionDate = State(initialValue: Self.parseDate(transaction.transactionDate) ?? Date())
        _status = State(initialValue: transaction.status?.rawValue ?? "pending")
        _purchasedBy = State(initialValue: transaction.purchasedBy ?? "")
        _transactionType = State(initialValue: transaction.transactionType?.rawValue ?? "purchase")
        _reimbursementType = State(initialValue: transaction.reimbursementType ?? "none")
        _budgetCategoryId = State(initialValue: transaction.budgetCategoryId)
        _hasEmailReceipt = State(initialValue: transaction.hasEmailReceipt ?? false)
        _subtotalText = State(initialValue: Self.centsToText(transaction.subtotalCents))
        _taxRateText = State(initialValue: transaction.taxRatePct.map { String(format: "%.2f", $0) } ?? "")
    }

    private var selectedCategory: BudgetCategory? {
        budgetCategories.first { $0.id == budgetCategoryId }
    }

    private var isItemizedCategory: Bool {
        selectedCategory?.metadata?.categoryType == .itemized
    }

    private var computedTaxAmount: String {
        guard let amount = textToCents(amountText),
              let subtotal = textToCents(subtotalText),
              amount > 0, subtotal > 0 else { return "—" }
        let tax = amount - subtotal
        return CurrencyFormatting.formatCentsWithDecimals(tax)
    }

    var body: some View {
        FormSheet(
            title: "Edit Details",
            primaryAction: FormSheetAction(title: "Save") {
                saveChanges()
            },
            secondaryAction: FormSheetAction(title: "Cancel") {
                dismiss()
            }
        ) {
            VStack(spacing: Spacing.lg) {
                // 1. Vendor/Source
                FormField(label: "Vendor / Source", text: $source, placeholder: "e.g. Amazon, Wayfair")

                // 2. Amount
                FormField(label: "Amount ($)", text: $amountText, placeholder: "0.00")
                    .platformKeyboardType(.decimalPad)

                // 3. Date
                FormDateField(label: "Date", date: $transactionDate)

                // 4. Status
                FormSelect(label: "Status", selection: $status, options:
                    TransactionStatus.allCases.map { ($0.rawValue, $0.displayLabel) }
                )

                // 5. Purchased By
                FormSelect(label: "Purchased By", selection: $purchasedBy, options: [
                    ("", "—"),
                    ("client-card", "Client Card"),
                    ("design-business", "Design Business"),
                    ("missing", "Missing"),
                ])

                // 6. Transaction Type
                FormSelect(label: "Transaction Type", selection: $transactionType, options:
                    TransactionType.allCases.map { ($0.rawValue, $0.displayLabel) }
                )

                // 7. Reimbursement Type
                FormSelect(label: "Reimbursement Type", selection: $reimbursementType, options: [
                    ("none", "None"),
                    ("owed-to-client", "Owed to Client"),
                    ("owed-to-company", "Owed to Business"),
                ])

                // 8. Budget Category
                FormPicker(
                    label: "Budget Category",
                    value: selectedCategory?.name ?? "",
                    placeholder: "No Category"
                ) {
                    showCategoryPicker = true
                }

                // 9. Email Receipt
                FormToggle(label: "Email Receipt", isOn: $hasEmailReceipt)

                // 10-11. Conditional: Subtotal + Tax Rate (only for itemized categories)
                if isItemizedCategory {
                    FormField(label: "Subtotal ($)", text: $subtotalText, placeholder: "0.00")
                        .platformKeyboardType(.decimalPad)

                    FormField(label: "Tax Rate (%)", text: $taxRateText, placeholder: "0.00")
                        .platformKeyboardType(.decimalPad)

                    // Read-only computed tax amount
                    DetailRow(label: "Tax Amount", value: computedTaxAmount, showDivider: false)
                }
            }
        }
        .adaptivePresentation(isPresented: $showCategoryPicker, style: .picker) {
            CategoryPickerList(
                categories: budgetCategories,
                selectedId: budgetCategoryId,
                onSelect: { category in
                    budgetCategoryId = category?.id
                }
            )
        }
    }

    // MARK: - Save

    private func saveChanges() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var fields: [String: Any] = [
            "source": source,
            "transactionDate": dateFormatter.string(from: transactionDate),
            "status": status,
            "purchasedBy": purchasedBy,
            "transactionType": transactionType,
            "reimbursementType": reimbursementType,
            "hasEmailReceipt": hasEmailReceipt,
        ]

        if let cents = textToCents(amountText) {
            fields["amountCents"] = cents
        }

        if let catId = budgetCategoryId {
            fields["budgetCategoryId"] = catId
        } else {
            fields["budgetCategoryId"] = NSNull()
        }

        if isItemizedCategory {
            if let subtotal = textToCents(subtotalText) {
                fields["subtotalCents"] = subtotal
            }
            if let rate = Double(taxRateText), rate > 0 {
                fields["taxRatePct"] = rate
            }
        }

        onSave(fields)
        dismiss()
    }

    // MARK: - Helpers

    private static func centsToText(_ cents: Int?) -> String {
        guard let cents, cents > 0 else { return "" }
        return String(format: "%.2f", Double(cents) / 100.0)
    }

    private func textToCents(_ text: String) -> Int? {
        guard let value = Double(text), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}
