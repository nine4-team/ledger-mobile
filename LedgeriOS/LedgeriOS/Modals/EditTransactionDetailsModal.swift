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
        _status = State(initialValue: transaction.status ?? "pending")
        _purchasedBy = State(initialValue: transaction.purchasedBy ?? "")
        _transactionType = State(initialValue: transaction.transactionType ?? "purchase")
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
                    .keyboardType(.decimalPad)

                // 3. Date
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Date")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    DatePicker("", selection: $transactionDate, displayedComponents: .date)
                        .labelsHidden()
                }

                // 4. Status
                pickerField(label: "Status", selection: $status, options: [
                    ("pending", "Pending"),
                    ("completed", "Completed"),
                    ("canceled", "Canceled"),
                    ("inventory-only", "Inventory Only"),
                ])

                // 5. Purchased By
                pickerField(label: "Purchased By", selection: $purchasedBy, options: [
                    ("", "—"),
                    ("client-card", "Client Card"),
                    ("design-business", "Design Business"),
                    ("missing", "Missing"),
                ])

                // 6. Transaction Type
                pickerField(label: "Transaction Type", selection: $transactionType, options: [
                    ("purchase", "Purchase"),
                    ("sale", "Sale"),
                    ("return", "Return"),
                    ("to-inventory", "To Inventory"),
                ])

                // 7. Reimbursement Type
                pickerField(label: "Reimbursement Type", selection: $reimbursementType, options: [
                    ("none", "None"),
                    ("owed-to-client", "Owed to Client"),
                    ("owed-to-company", "Owed to Business"),
                ])

                // 8. Budget Category
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Budget Category")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text(selectedCategory?.name ?? "No Category")
                                .font(Typography.body)
                                .foregroundStyle(
                                    selectedCategory != nil ? BrandColors.textPrimary : BrandColors.textTertiary
                                )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 44)
                        .background(BrandColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // 9. Email Receipt
                Toggle("Email Receipt", isOn: $hasEmailReceipt)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .tint(BrandColors.primary)

                // 10-11. Conditional: Subtotal + Tax Rate (only for itemized categories)
                if isItemizedCategory {
                    FormField(label: "Subtotal ($)", text: $subtotalText, placeholder: "0.00")
                        .keyboardType(.decimalPad)

                    FormField(label: "Tax Rate (%)", text: $taxRateText, placeholder: "0.00")
                        .keyboardType(.decimalPad)

                    // Read-only computed tax amount
                    DetailRow(label: "Tax Amount", value: computedTaxAmount, showDivider: false)
                }
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerList(
                categories: budgetCategories,
                selectedId: budgetCategoryId,
                onSelect: { category in
                    budgetCategoryId = category?.id
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Picker Helper

    @ViewBuilder
    private func pickerField(label: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            Picker(label, selection: selection) {
                ForEach(options, id: \.0) { value, display in
                    Text(display).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(BrandColors.textPrimary)
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
