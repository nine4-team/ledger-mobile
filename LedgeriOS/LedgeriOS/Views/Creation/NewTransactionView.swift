import SwiftUI

/// Creation context for transactions — project-scoped or inventory.
enum TransactionCreationContext {
    case project(String)
    case inventory
}

/// Multi-step bottom sheet form for creating a new transaction.
/// Step 1: Type selection → Step 2: Destination → Step 3: Details.
struct NewTransactionView: View {
    let context: TransactionCreationContext

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep = 1
    @State private var transactionType: TransactionType?

    // Step 2
    @State private var destination = ""

    // Step 3 — detail fields
    @State private var source = ""
    @State private var transactionDate = Date()
    @State private var amount = ""
    @State private var status: TransactionStatus = .pending
    @State private var purchasedBy = "design-business"
    @State private var reimbursementType = "none"
    @State private var notes = ""
    @State private var selectedCategoryId: String?
    @State private var hasEmailReceipt = false
    @State private var subtotal = ""
    @State private var taxRate = ""

    // Pickers
    @State private var showCategoryPicker = false
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

    var body: some View {
        Group {
            switch currentStep {
            case 1: step1TypeSelection
            case 2: step2Destination
            default: step3Details
            }
        }
        .adaptivePresentation(isPresented: $showCategoryPicker, style: .picker) {
            CategoryPickerList(
                categories: projectContext?.enabledBudgetCategories ?? [],
                selectedId: selectedCategoryId,
                onSelect: { cat in selectedCategoryId = cat?.id }
            )
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
            totalSteps: 3,
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
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Next") {
                currentStep = 3
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 1
            }
        ) {
            VStack(spacing: Spacing.md) {
                VendorPickerField(value: $destination, label: "Source / Vendor", showPicker: $showVendorPicker)
            }
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

    // MARK: - Step 3: Details

    private var step3Details: some View {
        MultiStepFormSheet(
            title: "New Transaction",

            currentStep: 3,
            totalSteps: 3,
            primaryAction: FormSheetAction(title: "Create Transaction", isDisabled: !isReadyToSubmit) {
                createTransaction()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = 2
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
                        Text("Status")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        SegmentedControl(selection: $status, options: TransactionStatus.allCases.map {
                            SegmentOption(id: $0, label: $0.displayLabel)
                        })
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Purchased By")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        SegmentedControl(selection: $purchasedBy, options: [
                            SegmentOption(id: "client-card", label: "Client Card"),
                            SegmentOption(id: "design-business", label: "Design Business"),
                        ])
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Reimbursement")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)
                        SegmentedControl(selection: $reimbursementType, options: [
                            SegmentOption(id: "none", label: "None"),
                            SegmentOption(id: "owed-to-client", label: "Owed to Client"),
                            SegmentOption(id: "owed-to-company", label: "Owed to Company"),
                        ])
                    }
                }

                // MARK: Additional Details
                formSection("Additional Details") {
                    FormField(text: $notes, placeholder: "Notes", axis: .vertical)

                    if projectId != nil {
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
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Email Receipt")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        Spacer()
                        Toggle("", isOn: $hasEmailReceipt)
                            .labelsHidden()
                            .tint(BrandColors.primary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                            .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    )
                }

                // MARK: Itemized Details (conditional)
                if isItemizedCategory {
                    formSection("Itemized Details") {
                        FormField(label: "Subtotal", text: $subtotal, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
                        FormField(label: "Tax Rate (%)", text: $taxRate, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
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
        return Int(round(value * 100))
    }
}
