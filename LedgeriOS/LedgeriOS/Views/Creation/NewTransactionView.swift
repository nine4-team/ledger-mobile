import SwiftUI

/// Creation context for transactions — project-scoped or inventory.
enum TransactionCreationContext {
    case project(String)
    case inventory
}

/// Where a transaction ultimately lives — a specific project, or the account's
/// inventory. Initialized from `TransactionCreationContext` and, for Purchase
/// with client-paid routing, editable by the user via the Destination step.
enum TransactionDestination: Hashable {
    case project(String)
    case inventory
}

/// Logical screens the New Transaction sheet can show. Ordering is defined by
/// `NewTransactionView.orderedSteps` based on the current branch.
enum TransactionCreationStep: Hashable {
    case typeSelection        // Fee / Expense / Purchase (items) / Return (items)
    case whoPaid              // Client / Design Business (Expense + Purchase)
    case destination          // Project picker (not auto-inventory routing)
    case budgetCategory       // pick a BudgetCategory
    case vendor               // vendor picker (skipped for Fee)
    case details              // full detail form
}

/// Multi-step bottom sheet form for creating a new transaction.
/// See docs/specs/transaction-creation.md and docs/specs/transaction-type.md for the flow spec.
struct NewTransactionView: View {
    let context: TransactionCreationContext
    var onCreated: ((Transaction) -> Void)?

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    // Step management
    @State private var currentStep: TransactionCreationStep = .typeSelection
    @State private var transactionType: TransactionType?
    @State private var selectedDestination: TransactionDestination
    @State private var createdTransactionId: String?

    // Vendor step
    @State private var vendor = ""
    @State private var otherVendorMode = false
    @State private var otherVendorText = ""
    @FocusState private var otherVendorFocused: Bool

    // Details fields
    @State private var source = ""
    @State private var transactionDate = Date()
    @State private var amount = ""
    @State private var purchasedBy = "design-business"
    @State private var needsReimbursement = false
    @State private var notes = ""
    @State private var selectedCategoryId: String?
    @State private var hasEmailReceipt = false
    @State private var subtotal = ""
    @State private var taxRate = ""

    // Pickers
    @State private var showVendorPicker = false

    private let transactionsService = TransactionsService()

    init(context: TransactionCreationContext, onCreated: ((Transaction) -> Void)? = nil) {
        self.context = context
        self.onCreated = onCreated
        switch context {
        case .project(let id):
            _selectedDestination = State(initialValue: .project(id))
        case .inventory:
            _selectedDestination = State(initialValue: .inventory)
        }
    }

    /// Entry-context projectId. Used only as a handoff to `ItemEntryFlowView`
    /// after an itemized purchase routes through inventory.
    private var entryProjectId: String? {
        switch context {
        case .project(let id): return id
        case .inventory: return nil
        }
    }

    private var isItemized: Bool {
        transactionType == .purchase || transactionType == .return
    }

    /// `.purchase` with business-paid auto-routes to inventory (projectId cleared).
    private var autoInventoryRouting: Bool {
        transactionType == .purchase && purchasedBy == "design-business"
    }

    /// Fee: counterparty is the business; who-paid is always the business.
    /// Return: items physically go back to a vendor; who-paid doesn't apply.
    private var skipWhoPaid: Bool {
        transactionType == .fee || transactionType == .return
    }

    private var skipVendor: Bool { transactionType == .fee }

    private var showsReimbursementToggle: Bool { transactionType == .expense }

    /// The project the transaction will land on, if any. `nil` means the
    /// transaction lives on inventory (no project).
    private var destinationProjectId: String? {
        if case .project(let id) = selectedDestination { return id }
        return nil
    }

    /// The ordered list of steps for the current branch.
    private var orderedSteps: [TransactionCreationStep] {
        guard let type = transactionType else { return [.typeSelection] }

        var steps: [TransactionCreationStep] = [.typeSelection]
        if !skipWhoPaid { steps.append(.whoPaid) }
        if !autoInventoryRouting { steps.append(.destination) }
        if destinationProjectId != nil { steps.append(.budgetCategory) }
        if !skipVendor { steps.append(.vendor) }
        steps.append(.details)
        _ = type // silence unused
        return steps
    }

    private var currentStepIndex: Int {
        (orderedSteps.firstIndex(of: currentStep) ?? 0) + 1
    }

    private var totalSteps: Int { orderedSteps.count }

    private func advance() {
        guard let i = orderedSteps.firstIndex(of: currentStep),
              i + 1 < orderedSteps.count else { return }
        currentStep = orderedSteps[i + 1]
    }

    private func goBack() {
        guard let i = orderedSteps.firstIndex(of: currentStep),
              i > 0 else { return }
        currentStep = orderedSteps[i - 1]
    }

    private var isReadyToSubmit: Bool {
        TransactionFormValidation.isTransactionReadyToSubmit(type: transactionType)
    }

    /// Active (non-archived) categories for the currently selected destination project.
    private var destinationCategories: [BudgetCategory] {
        guard let pid = destinationProjectId else { return [] }
        return accountContext.allBudgetCategories
            .filter { $0.projectId == pid && $0.isArchived != true }
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
    }

    private var selectedCategory: BudgetCategory? {
        destinationCategories.first { $0.id == selectedCategoryId }
    }

    var body: some View {
        Group {
            if let txId = createdTransactionId {
                ItemEntryFlowView(
                    transactionId: txId,
                    budgetCategoryId: selectedCategoryId,
                    originProjectId: entryProjectId
                )
            } else {
                switch currentStep {
                case .typeSelection: stepTypeSelection
                case .whoPaid: stepWhoPaid
                case .destination: stepDestination
                case .budgetCategory: stepBudgetCategory
                case .vendor: stepVendor
                case .details: stepDetails
                }
            }
        }
        .onChange(of: selectedDestination) { _, _ in
            // Destination change invalidates the category pick — categories
            // are scoped to a project.
            selectedCategoryId = nil
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(
                selectedValue: vendor.isEmpty ? source : vendor,
                onSelect: { newValue in
                    if currentStep == .vendor || !vendor.isEmpty {
                        vendor = newValue
                    } else {
                        source = newValue
                    }
                }
            )
        }
    }

    // MARK: - Step: Type Selection

    private var stepTypeSelection: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "What type of transaction?",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Cancel") { dismiss() }
        ) {
            VStack(spacing: Spacing.md) {
                typeCard("Fee", icon: "banknote", type: .fee)
                typeCard("Expense", icon: "tray", type: .expense)
                typeCard("Purchase (items)", icon: "cart", type: .purchase)
                typeCard("Return (items)", icon: "arrow.uturn.left", type: .return)
            }
        }
    }

    private func typeCard(_ label: String, icon: String, type: TransactionType) -> some View {
        Button {
            transactionType = type
            selectedCategoryId = nil
            if type == .fee {
                applyFeeImplicitValues()
            }
            advance()
        } label: {
            optionCardLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
    }

    /// Fee implicit values: who paid is the business, counterparty is the
    /// business itself. Reimbursement is left as `none` (not a handoff).
    private func applyFeeImplicitValues() {
        purchasedBy = "design-business"
        source = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        vendor = ""
    }

    // MARK: - Step: Who Paid

    private var stepWhoPaid: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "Who paid?",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            VStack(spacing: Spacing.md) {
                whoPaidCard("Design Business", icon: "building.2", value: "design-business")
                whoPaidCard("Client", icon: "person", value: "client-card")
            }
        }
    }

    private func whoPaidCard(_ label: String, icon: String, value: String) -> some View {
        Button {
            purchasedBy = value
            advance()
        } label: {
            optionCardLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step: Destination (project picker)

    private var stepDestination: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "Which project?",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: !destinationIsProject
            ) { advance() },
            secondaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            InlineOptionPicker(selection: $selectedDestination, options: destinationOptions)
        }
    }

    private var destinationOptions: [InlineOption<TransactionDestination>] {
        accountContext.allProjects
            .filter { $0.isArchived != true }
            .compactMap { proj -> InlineOption<TransactionDestination>? in
                guard let id = proj.id else { return nil }
                return InlineOption(id: TransactionDestination.project(id), label: proj.name)
            }
    }

    private var destinationIsProject: Bool {
        if case .project = selectedDestination { return true }
        return false
    }

    // MARK: - Step: Budget Category

    private var stepBudgetCategory: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "Assign a budget category",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: selectedCategoryId == nil
            ) { advance() },
            secondaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            InlineOptionPicker(selection: $selectedCategoryId, options: categoryOptions)
        }
    }

    /// Budget-category options filtered to categories whose `supportedTypes`
    /// include the picked transaction type.
    private var categoryOptions: [InlineOption<String?>] {
        guard let type = transactionType else { return [] }
        let filtered = destinationCategories.filter {
            $0.resolvedSupportedTypes.contains(type)
        }
        return filtered.map { InlineOption(id: $0.id, label: $0.name) }
    }

    // MARK: - Step: Vendor

    private var stepVendor: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: vendorPrompt,

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Next", isDisabled: vendor.isEmpty && (!otherVendorMode || otherVendorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) {
                if otherVendorMode {
                    vendor = otherVendorText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                advance()
            },
            secondaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            InlineVendorPicker(
                selectedValue: $vendor,
                otherMode: $otherVendorMode,
                otherText: $otherVendorText,
                otherFocused: $otherVendorFocused
            )
        }
    }

    private var vendorPrompt: String {
        switch transactionType {
        case .purchase: return "Where was this purchased?"
        case .sale: return "Who was this sold to?"
        case .return: return "Where was this returned?"
        case .expense: return "Paid to whom?"
        case .fee, nil: return "Vendor"
        }
    }

    // MARK: - Details

    private var stepDetails: some View {
        MultiStepFormSheet(
            title: "New Transaction",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Create Transaction", isDisabled: !isReadyToSubmit) {
                createTransaction()
            },
            secondaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            VStack(spacing: Spacing.xl) {
                // MARK: Transaction Info
                formSection("Transaction Info") {
                    if transactionType != .fee {
                        if !vendor.isEmpty {
                            VendorPickerField(value: $vendor, label: "Source / Vendor", showPicker: $showVendorPicker)
                        } else {
                            VendorPickerField(value: $source, label: "Source / Vendor", showPicker: $showVendorPicker)
                        }
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

                // MARK: Additional Details
                formSection("Additional Details") {
                    if isItemized {
                        FormField(label: "Subtotal", text: $subtotal, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
                        FormField(label: "Tax Rate (%)", text: $taxRate, placeholder: "0.00")
                            .platformKeyboardType(.decimalPad)
                    }

                    if showsReimbursementToggle {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Does this need to be reimbursed?")
                                .font(Typography.label)
                                .foregroundStyle(BrandColors.textSecondary)
                            InlineOptionPicker(selection: $needsReimbursement, options: [
                                InlineOption(id: false, label: "No"),
                                InlineOption(id: true, label: "Yes"),
                            ])
                        }
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

    // MARK: - Shared Option Card

    @ViewBuilder
    private func optionCardLabel(_ label: String, icon: String) -> some View {
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

        let effectiveSource = vendor.isEmpty ? source : vendor
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var transaction = Transaction()
        transaction.projectId = destinationProjectId
        transaction.transactionType = transactionType
        transaction.source = effectiveSource.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.transactionDate = dateFormatter.string(from: transactionDate)
        transaction.amountCents = parseCents(amount)
        transaction.purchasedBy = purchasedBy
        transaction.reimbursementType = resolvedReimbursementType
        transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.hasEmailReceipt = hasEmailReceipt

        let routeThroughInventory = autoInventoryRouting

        transaction.budgetCategoryId = selectedCategoryId
        if isItemized {
            transaction.subtotalCents = parseCents(subtotal)
            if let rate = Double(taxRate.trimmingCharacters(in: .whitespacesAndNewlines)) {
                transaction.taxRatePct = rate
            }
        }
        if routeThroughInventory {
            transaction.projectId = nil
        }

        do {
            let txId = try transactionsService.createTransaction(accountId: accountId, transaction: transaction)
            if routeThroughInventory {
                createdTransactionId = txId
            } else {
                transaction.id = txId
                onCreated?(transaction)
                dismiss()
            }
        } catch {
            // Offline-first: should not fail
        }
    }

    /// Narrow-semantic reimbursement derivation:
    /// - Expense with the "needs reimbursement" toggle on → direction inferred
    ///   from who paid (client-paid → owed-to-client; business-paid → owed-to-company).
    /// - Everything else → nil. Fees, Purchases, Returns, Sales, toggle-off all
    ///   leave this empty.
    private var resolvedReimbursementType: String? {
        guard showsReimbursementToggle, needsReimbursement else { return nil }
        return purchasedBy == "design-business" ? "owed-to-company" : "owed-to-client"
    }

    private func parseCents(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int(round(value * 100))
    }
}
