import SwiftUI

/// Creation context for transactions — project-scoped or inventory.
enum TransactionCreationContext {
    case project(String)
    case inventory
}

/// Multi-step bottom sheet form for creating a new transaction.
/// Step 1: Type selection → Step 2: Destination → Step 3: Budget Category (project only) → Step 4: Details.
struct NewTransactionView: View {
    let context: TransactionCreationContext

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep = 1
    @State private var transactionType: TransactionType?
    @State private var createdTransactionId: String?

    // Step 2
    @State private var destination = ""
    @State private var otherVendorMode = false
    @State private var otherVendorText = ""
    @FocusState private var otherVendorFocused: Bool

    // Step 3 — detail fields
    @State private var source = ""
    @State private var transactionDate = Date()
    @State private var amount = ""
    @State private var status: TransactionStatus = .completed
    @State private var purchasedBy = "design-business"
    @State private var reimbursementType = "none"
    @State private var notes = ""
    @State private var selectedCategoryId: String?
    @State private var hasEmailReceipt = false
    @State private var subtotal = ""
    @State private var taxRate = ""

    // Pickers
    @State private var showVendorPicker = false

    private let transactionsService = TransactionsService()

    private var projectId: String? {
        switch context {
        case .project(let id): return id
        case .inventory: return nil
        }
    }

    private var isReadyToSubmit: Bool {
        TransactionFormValidation.isTransactionReadyToSubmit(type: transactionType)
    }

    private var selectedCategory: BudgetCategory? {
        projectContext?.enabledBudgetCategories.first { $0.id == selectedCategoryId }
    }

    private var isItemizedCategory: Bool {
        selectedCategory?.metadata?.categoryType == .itemized
    }

    private var hasCategories: Bool {
        projectId != nil
    }

    private var totalSteps: Int {
        hasCategories ? 4 : 3
    }

    private var detailsStep: Int {
        hasCategories ? 4 : 3
    }

    var body: some View {
        Group {
            if let txId = createdTransactionId {
                ItemEntryFlowView(
                    transactionId: txId,
                    budgetCategoryId: selectedCategoryId,
                    originProjectId: projectId
                )
            } else {
                switch currentStep {
                case 1: step1TypeSelection
                case 2: step2Destination
                case 3 where hasCategories: step3BudgetCategory
                default: stepDetails
                }
            }
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(
                selectedValue: destination.isEmpty ? source : destination,
                onSelect: { newValue in
                    if currentStep == 2 || !destination.isEmpty {
                        destination = newValue
                    } else {
                        source = newValue
                    }
                }
            )
        }
    }

    // MARK: - Step 1: Type Selection

    private var step1TypeSelection: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "What type of transaction?",

            currentStep: 1,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Cancel") { dismiss() }
        ) {
            VStack(spacing: Spacing.md) {
                typeCard("Purchase", icon: "cart", type: .purchase)
                typeCard("Sale", icon: "dollarsign.circle", type: .sale)
                typeCard("Return", icon: "arrow.uturn.left", type: .return)
            }
        }
    }

    private func typeCard(_ label: String, icon: String, type: TransactionType) -> some View {
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
            .contentShape(Rectangle())
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
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Next", isDisabled: destination.isEmpty && (!otherVendorMode || otherVendorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) {
                if otherVendorMode {
                    destination = otherVendorText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                currentStep = 3
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 1
            }
        ) {
            InlineVendorPicker(
                selectedValue: $destination,
                otherMode: $otherVendorMode,
                otherText: $otherVendorText,
                otherFocused: $otherVendorFocused
            )
        }
    }

    private var destinationPrompt: String {
        switch transactionType {
        case .purchase: return "Where was this purchased?"
        case .sale: return "Who was this sold to?"
        case .return: return "Where was this returned?"
        case nil: return "Source"
        }
    }

    // MARK: - Step 3: Budget Category (project only)

    private var step3BudgetCategory: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "Assign a budget category",

            currentStep: 3,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Next") {
                currentStep = detailsStep
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 2
            }
        ) {
            InlineOptionPicker(selection: $selectedCategoryId, options:
                [InlineOption(id: nil as String?, label: "No Category")] +
                (projectContext?.enabledBudgetCategories ?? [])
                    .filter { $0.isArchived != true }
                    .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
                    .map { InlineOption(id: $0.id, label: $0.name) }
            )
        }
    }

    // MARK: - Details

    private var stepDetails: some View {
        MultiStepFormSheet(
            title: "New Transaction",

            currentStep: detailsStep,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Create Transaction", isDisabled: !isReadyToSubmit) {
                createTransaction()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = detailsStep - 1
            }
        ) {
            VStack(spacing: Spacing.xl) {
                // MARK: Transaction Info
                formSection("Transaction Info") {
                    if !destination.isEmpty {
                        VendorPickerField(value: $destination, label: "Source / Vendor", showPicker: $showVendorPicker)
                    } else {
                        VendorPickerField(value: $source, label: "Source / Vendor", showPicker: $showVendorPicker)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Date")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        DatePicker("", selection: $transactionDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    FormField(label: "Amount", text: $amount, placeholder: "0.00")
                        .platformKeyboardType(.decimalPad)
                }

                // MARK: Classification
                formSection("Classification") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Purchased By")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        InlineOptionPicker(selection: $purchasedBy, options: [
                            InlineOption(id: "client-card", label: "Client Card"),
                            InlineOption(id: "design-business", label: "Design Business"),
                        ])
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Reimbursement")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        InlineOptionPicker(selection: $reimbursementType, options: [
                            InlineOption(id: "none", label: "None"),
                            InlineOption(id: "owed-to-client", label: "Owed to Client"),
                            InlineOption(id: "owed-to-company", label: "Owed to Company"),
                        ])
                    }
                }

                // MARK: Additional Details
                formSection("Additional Details") {
                    if isItemizedCategory {
                        FormField(label: "Subtotal", text: $subtotal, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
                        FormField(label: "Tax Rate (%)", text: $taxRate, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
                    }

                    FormField(text: $notes, placeholder: "Notes", axis: .vertical)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Email Receipt")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        InlineOptionPicker(selection: $hasEmailReceipt, options: [
                            InlineOption(id: false, label: "No"),
                            InlineOption(id: true, label: "Yes"),
                        ])
                    }
                }
            }
        }
    }

    // MARK: - Section Helper

    @ViewBuilder
    private func formSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .sectionLabelStyle()
            content()
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
        transaction.hasEmailReceipt = hasEmailReceipt

        if isItemizedCategory {
            // Itemized categories route through inventory — items are added next
            transaction.projectId = nil
            transaction.budgetCategoryId = selectedCategoryId
            transaction.subtotalCents = parseCents(subtotal)
            if let rate = Double(taxRate.trimmingCharacters(in: .whitespacesAndNewlines)) {
                transaction.taxRatePct = rate
            }
        } else {
            transaction.budgetCategoryId = selectedCategoryId
        }

        do {
            let txId = try transactionsService.createTransaction(accountId: accountId, transaction: transaction)
            if isItemizedCategory {
                createdTransactionId = txId
            } else {
                dismiss()
            }
        } catch {
            // Offline-first: should not fail
        }
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(round(value * 100))
    }
}
