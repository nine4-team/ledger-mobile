import SwiftUI

/// Multi-step bottom sheet form for creating a new transaction.
/// Step 1: Type selection → Step 2: Destination → Step 3: Details.
struct NewTransactionView: View {
    let projectId: String

    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep = 1
    @State private var transactionType: String?

    // Step 2
    @State private var destination = ""

    // Step 3 — detail fields
    @State private var source = ""
    @State private var transactionDate = Date()
    @State private var amount = ""
    @State private var status = "pending"
    @State private var purchasedBy = "design-business"
    @State private var reimbursementType = "none"
    @State private var notes = ""
    @State private var selectedCategoryId: String?
    @State private var hasEmailReceipt = false
    @State private var subtotal = ""
    @State private var taxRate = ""

    // Pickers
    @State private var showCategoryPicker = false

    private let transactionsService = TransactionsService(syncTracker: NoOpSyncTracker())

    private var isReadyToSubmit: Bool {
        TransactionFormValidation.isTransactionReadyToSubmit(type: transactionType)
    }

    private var selectedCategory: BudgetCategory? {
        projectContext.budgetCategories.first { $0.id == selectedCategoryId }
    }

    private var isItemizedCategory: Bool {
        selectedCategory?.metadata?.categoryType == .itemized
    }

    var body: some View {
        Group {
            switch currentStep {
            case 1: step1TypeSelection
            case 2: step2Destination
            default: step3Details
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerList(
                categories: projectContext.budgetCategories,
                selectedId: selectedCategoryId,
                onSelect: { cat in selectedCategoryId = cat?.id }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Step 1: Type Selection

    private var step1TypeSelection: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "What type of transaction?",
            currentStep: 1,
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Cancel") { dismiss() }
        ) {
            VStack(spacing: Spacing.md) {
                typeCard("Purchase", icon: "cart", type: "purchase")
                typeCard("Sale", icon: "dollarsign.circle", type: "sale")
                typeCard("Return", icon: "arrow.uturn.left", type: "return")
                typeCard("To Inventory", icon: "shippingbox", type: "to-inventory")
            }
        }
    }

    private func typeCard(_ label: String, icon: String, type: String) -> some View {
        Button {
            transactionType = type
            currentStep = 2
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(BrandColors.primary)

                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(BrandColors.textSecondary)
            }
            .padding(Spacing.md)
            .background(BrandColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Destination

    private var step2Destination: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: destinationPrompt,
            currentStep: 2,
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Next") {
                currentStep = 3
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 1
            }
        ) {
            VStack(spacing: Spacing.md) {
                FormField(label: "Source / Vendor", text: $destination, placeholder: "e.g. HomeGoods, Ross")
            }
        }
    }

    private var destinationPrompt: String {
        switch transactionType {
        case "purchase": return "Where was this purchased?"
        case "sale": return "Who was this sold to?"
        case "return": return "Where was this returned?"
        default: return "Source"
        }
    }

    // MARK: - Step 3: Details

    private var step3Details: some View {
        FormSheet(
            title: "New Transaction",
            primaryAction: FormSheetAction(title: "Create Transaction", isDisabled: !isReadyToSubmit) {
                createTransaction()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 2
            }
        ) {
            VStack(spacing: Spacing.md) {
                Text("Step 3 of 3")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                if !destination.isEmpty {
                    FormField(label: "Source / Vendor", text: $destination, placeholder: "e.g. HomeGoods")
                } else {
                    FormField(label: "Source / Vendor", text: $source, placeholder: "e.g. HomeGoods")
                }

                // Date
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Date")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    DatePicker("", selection: $transactionDate, displayedComponents: .date)
                        .labelsHidden()
                }

                // Amount
                FormField(label: "Amount", text: $amount, placeholder: "$0.00")
                    .keyboardType(.decimalPad)

                // Status
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Status")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    Picker("Status", selection: $status) {
                        Text("Pending").tag("pending")
                        Text("Completed").tag("completed")
                        Text("Canceled").tag("canceled")
                        Text("Inventory Only").tag("inventory-only")
                    }
                    .pickerStyle(.segmented)
                }

                // Purchased By
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Purchased By")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    Picker("Purchased By", selection: $purchasedBy) {
                        Text("Client Card").tag("client-card")
                        Text("Design Business").tag("design-business")
                    }
                    .pickerStyle(.segmented)
                }

                // Reimbursement Type
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Reimbursement Type")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    Picker("Reimbursement", selection: $reimbursementType) {
                        Text("None").tag("none")
                        Text("Owed to Client").tag("owed-to-client")
                        Text("Owed to Company").tag("owed-to-company")
                    }
                    .pickerStyle(.segmented)
                }

                // Notes
                FormField(label: "Notes", text: $notes, placeholder: "Optional notes", axis: .vertical)

                // Budget Category
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Budget Category")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)

                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text(selectedCategory?.name ?? "Select Category")
                                .foregroundStyle(
                                    selectedCategory != nil ? BrandColors.textPrimary : BrandColors.textSecondary
                                )
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        .font(Typography.input)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 44)
                        .background(BrandColors.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                        )
                    }
                }

                // Email Receipt
                Toggle("Email Receipt", isOn: $hasEmailReceipt)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .tint(BrandColors.primary)

                // Conditional: Itemized category fields
                if isItemizedCategory {
                    FormField(label: "Subtotal", text: $subtotal, placeholder: "$0.00")
                        .keyboardType(.decimalPad)
                    FormField(label: "Tax Rate (%)", text: $taxRate, placeholder: "0.0")
                        .keyboardType(.decimalPad)
                }
            }
        }
    }

    // MARK: - Actions

    private func createTransaction() {
        guard let accountId = accountContext.currentAccountId else { return }

        let effectiveSource = destination.isEmpty ? source : destination
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var transaction = Transaction()
        transaction.projectId = projectId
        transaction.transactionType = transactionType
        transaction.source = effectiveSource.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.transactionDate = dateFormatter.string(from: transactionDate)
        transaction.amountCents = parseCents(amount)
        transaction.status = status
        transaction.purchasedBy = purchasedBy
        transaction.reimbursementType = reimbursementType == "none" ? nil : reimbursementType
        transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.budgetCategoryId = selectedCategoryId
        transaction.hasEmailReceipt = hasEmailReceipt

        if isItemizedCategory {
            transaction.subtotalCents = parseCents(subtotal)
            if let rate = Double(taxRate.trimmingCharacters(in: .whitespacesAndNewlines)) {
                transaction.taxRatePct = rate
            }
        }

        do {
            _ = try transactionsService.createTransaction(accountId: accountId, transaction: transaction)
            dismiss()
        } catch {
            // Offline-first: should not fail
        }
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(value * 100)
    }
}
