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

enum TransactionDestinationResolver {
    static func options(projects: [Project]) -> [InlineOption<TransactionDestination>] {
        let projectOptions = projects
            .filter { $0.isArchived != true }
            .compactMap { project -> InlineOption<TransactionDestination>? in
                guard let id = project.id else { return nil }
                return InlineOption(id: .project(id), label: project.name)
            }

        return [InlineOption(id: .inventory, label: "Inventory")] + projectOptions
    }
}

/// Logical screens the New Transaction sheet can show. Ordering is defined by
/// `NewTransactionView.orderedSteps` based on the current branch.
/// How the user is supplying tax info on an itemized transaction.
/// `.rate` — user types the %, subtotal is derived.
/// `.subtotal` — user types the pre-tax subtotal, rate is derived.
/// `.none` — no tax; subtotal equals the amount.
enum TaxMode: Hashable { case none, rate, subtotal }

enum TransactionCreationStep: Hashable {
    case typeSelection        // Purchase / Return / Client Payment
    case whoPaid              // Client / Design Business (Purchase)
    case destination          // Project picker (not auto-inventory routing)
    case budgetCategory       // pick a BudgetCategory
    case vendor               // vendor/source picker
    case details              // full detail form
}

enum TransactionCreationStepResolver {
    static func orderedSteps(
        type: TransactionType?,
        context: TransactionCreationContext,
        destinationProjectId: String?,
        skipVendor: Bool = false
    ) -> [TransactionCreationStep] {
        guard let type else { return [.typeSelection] }

        var steps: [TransactionCreationStep] = [.typeSelection]
        if type == .purchase { steps.append(.whoPaid) }
        if shouldSelectDestination(for: context) { steps.append(.destination) }
        if destinationProjectId != nil { steps.append(.budgetCategory) }
        if !skipVendor { steps.append(.vendor) }
        steps.append(.details)
        return steps
    }

    private static func shouldSelectDestination(for context: TransactionCreationContext) -> Bool {
        if case .inventory = context { return true }
        return false
    }
}

/// Multi-step bottom sheet form for creating a new transaction.
/// See docs/specs/transaction-creation.md and docs/specs/transaction-type.md for the flow spec.
struct NewTransactionView: View {
    let context: TransactionCreationContext
    var onCreated: ((Transaction) -> Void)?

    @Environment(ProjectContext.self) private var projectContext: ProjectContext?
    @Environment(AccountContext.self) private var accountContext
    @Environment(MediaService.self) private var mediaService
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
    @State private var saveOtherVendorAsPreset = false
    @FocusState private var otherVendorFocused: Bool

    // Details fields
    @State private var source = ""
    @State private var transactionDate: Date? = nil
    @State private var amount = ""
    @State private var purchasedBy = "design-business"
    @State private var needsReimbursement = false
    @State private var notes = ""
    @State private var selectedCategoryId: String?
    @State private var hasEmailReceipt = false
    @State private var subtotal = ""
    @State private var taxRate = ""
    @State private var taxMode: TaxMode = .rate
    @State private var receiptImages: [AttachmentRef] = []

    /// Pre-allocated Firestore doc ID. Used as the storage `entityId` for
    /// receipt uploads so attachments live under the eventual transaction's
    /// path even before the document is written. Resolved lazily on first use.
    @State private var pendingTransactionId: String?

    // Pickers
    @State private var showVendorPicker = false

    // Submission error surfaced on the details step when create throws.
    @State private var submissionError: String?

    // Categories enabled for the destination project (ids present in
    // `accounts/{aid}/projects/{pid}/budgetCategories`). Subscribed to when
    // `destinationProjectId` changes.
    @State private var enabledCategoryIds: Set<String> = []

    private let transactionsService = TransactionsService()
    private let vendorDefaultsService = VendorDefaultsService()
    private let projectBudgetCategoriesService: ProjectBudgetCategoriesServiceProtocol = ProjectBudgetCategoriesService()

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
    /// after a business-paid itemized category routes through inventory.
    private var entryProjectId: String? {
        switch context {
        case .project(let id): return id
        case .inventory: return nil
        }
    }

    /// The built-in inventory source is always available in the source picker.
    private var inventorySourceLabel: String {
        InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
    }

    private var fixedSourceOptions: [String] {
        destinationProjectId == nil ? [] : [inventorySourceLabel]
    }

    /// An inventory-bound transaction must name the outside vendor it came
    /// from, not inventory itself (which would imply Inventory → Inventory).
    private var excludedSourceOptions: Set<String> {
        destinationProjectId == nil ? ["Inventory", inventorySourceLabel] : []
    }

    /// Inventory routing is a category + purchaser decision, matching the
    /// pre-taxonomy flow: business-paid itemized categories go through business
    /// inventory first. Plain purchases/services do not.
    private var routeThroughInventory: Bool {
        TransactionFormValidation.shouldRouteThroughInventory(
            type: transactionType,
            isItemizedCategory: isItemizedCategory,
            purchasedBy: purchasedBy
        )
    }

    /// Itemized behavior is still owned by budget category metadata.
    private var isItemizedCategory: Bool {
        if selectedCategory?.metadata?.categoryType == .itemized { return true }
        return selectedCategory?.isItemsCategory == true
    }

    private var skipVendor: Bool { transactionType == .paymentToBusiness }

    private var showsReimbursementToggle: Bool { transactionType == .purchase }

    private var showsSourceVendorField: Bool { transactionType != .paymentToBusiness }

    /// The project the transaction will land on, if any. `nil` means the
    /// transaction lives on inventory (no project).
    private var destinationProjectId: String? {
        if case .project(let id) = selectedDestination { return id }
        return nil
    }

    /// The ordered list of steps for the current branch.
    private var orderedSteps: [TransactionCreationStep] {
        TransactionCreationStepResolver.orderedSteps(
            type: transactionType,
            context: context,
            destinationProjectId: destinationProjectId,
            skipVendor: skipVendor
        )
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
        guard destinationProjectId != nil else { return [] }
        return accountContext.allBudgetCategories
            .filter { cat in
                guard let id = cat.id, enabledCategoryIds.contains(id) else { return false }
                return cat.isArchived != true
            }
            .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
    }

    private var selectedCategory: BudgetCategory? {
        destinationCategories.first { $0.id == selectedCategoryId }
    }

    /// Composite key that drives re-subscription when the destination project
    /// or the current account changes.
    private var subscriptionKey: String {
        "\(accountContext.currentAccountId ?? "")|\(destinationProjectId ?? "")"
    }

    private func subscribeToEnabledCategories() async {
        guard let accountId = accountContext.currentAccountId,
              let projectId = destinationProjectId else {
            enabledCategoryIds = []
            return
        }
        let listener = projectBudgetCategoriesService.subscribeToProjectBudgetCategories(
            accountId: accountId,
            projectId: projectId
        ) { pbcs in
            Task { @MainActor in
                enabledCategoryIds = Set(pbcs.compactMap(\.id))
            }
        }
        // Keep the listener alive until the task is cancelled (destination
        // changes or view disappears), then tear it down.
        await withTaskCancellationHandler {
            try? await Task.sleep(nanoseconds: .max)
        } onCancel: {
            listener.remove()
        }
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
        .onChange(of: taxMode) { _, newMode in
            switch newMode {
            case .none:
                subtotal = ""
                taxRate = ""
            case .rate:
                subtotal = ""
            case .subtotal:
                taxRate = ""
            }
        }
        .task(id: subscriptionKey) {
            await subscribeToEnabledCategories()
        }
        .adaptivePresentation(isPresented: $showVendorPicker, style: .picker) {
            VendorPickerModal(
                selectedValue: vendor.isEmpty ? source : vendor,
                fixedOptions: fixedSourceOptions,
                excludedOptions: excludedSourceOptions,
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
                typeCard("Purchase", icon: "cart", type: .purchase)
                typeCard("Return", icon: "arrow.uturn.left", type: .return)
                typeCard("Client Payment", icon: "dollarsign.circle", type: .paymentToBusiness)
            }
        }
    }

    private func typeCard(_ label: String, icon: String, type: TransactionType) -> some View {
        Button {
            transactionType = type
            selectedCategoryId = nil
            advance()
        } label: {
            optionCardLabel(label, icon: icon)
        }
        .buttonStyle(.plain)
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

    // MARK: - Step: Destination

    private var stepDestination: some View {
        MultiStepFormSheet(
            title: "New Transaction",
            description: "Where should this transaction go?",

            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            primaryAction: FormSheetAction(title: "Next") { advance() },
            secondaryAction: FormSheetAction(title: "Back") { goBack() }
        ) {
            InlineOptionPicker(selection: $selectedDestination, options: destinationOptions)
        }
    }

    private var destinationOptions: [InlineOption<TransactionDestination>] {
        TransactionDestinationResolver.options(projects: accountContext.allProjects)
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

    /// Budget-category options filtered to categories that accept the picked
    /// transaction type without relying on unsupported mixed category shapes.
    private var categoryOptions: [InlineOption<String?>] {
        guard let type = transactionType else { return [] }
        let filtered = destinationCategories.filter {
            category($0, accepts: type)
        }
        return filtered.map { InlineOption(id: $0.id, label: $0.name) }
    }

    private func category(_ category: BudgetCategory, accepts type: TransactionType) -> Bool {
        switch type {
        case .purchase:
            return category.resolvedCategoryType != .fee
        case .return:
            return category.isItemsCategory
        case .paymentToBusiness:
            return category.isFeeCategory
        case .sale, .fee, .expense:
            return false
        }
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
            VStack(alignment: .leading, spacing: Spacing.md) {
                inventoryRoutingNote
                InlineVendorPicker(
                    selectedValue: $vendor,
                    otherMode: $otherVendorMode,
                    otherText: $otherVendorText,
                    saveOtherAsPreset: $saveOtherVendorAsPreset,
                    otherFocused: $otherVendorFocused,
                    fixedOptions: fixedSourceOptions,
                    excludedOptions: excludedSourceOptions
                )
            }
        }
    }

    private var vendorPrompt: String {
        switch transactionType {
        case .purchase: return "Where was this purchased?"
        case .sale: return "Who was this sold to?"
        case .return: return "Where was this returned?"
        case .expense: return "Paid to whom?"
        case .fee, .paymentToBusiness, nil: return "Vendor"
        }
    }

    /// Surfaces the category-based inventory routing rule once the selected
    /// category proves this is an itemized, business-paid purchase.
    @ViewBuilder
    private var inventoryRoutingNote: some View {
        if routeThroughInventory {
            let projectName = originProject?.name
            let suffix = projectName.map { " You'll be offered to sell items to \($0) after." }
                ?? " You'll be offered to sell items to a project after."
            let prefix = "This itemized business purchase will be recorded in inventory first."
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(BrandColors.primary)
                    .padding(.top, 2)
                Text("\(prefix)\(suffix)")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
    }

    /// The project the user was inside when they opened the form, if any.
    /// Used only for display messaging — the actual routing is decided by the
    /// selected category and purchaser.
    private var originProject: Project? {
        guard let id = entryProjectId else { return nil }
        return accountContext.allProjects.first { $0.id == id }
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
            secondaryAction: FormSheetAction(title: "Back") { goBack() },
            error: submissionError
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                inventoryRoutingNote
                if showsSourceVendorField {
                    if !vendor.isEmpty {
                        VendorPickerField(
                            value: $vendor,
                            label: "Source / Vendor",
                            showPicker: $showVendorPicker,
                            fixedOptions: fixedSourceOptions,
                            excludedOptions: excludedSourceOptions
                        )
                    } else {
                        VendorPickerField(
                            value: $source,
                            label: "Source / Vendor",
                            showPicker: $showVendorPicker,
                            fixedOptions: fixedSourceOptions,
                            excludedOptions: excludedSourceOptions
                        )
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Date")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    if transactionDate == nil {
                        Button {
                            transactionDate = Date()
                        } label: {
                            HStack {
                                Text("Select date")
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textSecondary)
                                Spacer()
                                Image(systemName: "calendar")
                                    .foregroundStyle(BrandColors.textSecondary)
                            }
                            .padding(Spacing.sm)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                    .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { transactionDate ?? Date() },
                                set: { transactionDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }

                FormField(label: "Amount", text: $amount, placeholder: "0.00")
                    .platformKeyboardType(.decimalPad)

                if isItemizedCategory {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Tax Rate")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        if taxMode == .rate {
                            Text("Don't know the %? Enter the subtotal and we'll calculate it.")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }

                        HStack(spacing: Spacing.xs) {
                            horizontalOptionCard(selection: $taxMode, value: .rate, label: "Tax %")
                            horizontalOptionCard(selection: $taxMode, value: .subtotal, label: "Subtotal")
                            horizontalOptionCard(selection: $taxMode, value: .none, label: "No tax")
                        }

                        switch taxMode {
                        case .none:
                            EmptyView()
                        case .rate:
                            FormField(text: $taxRate, placeholder: "0.00")
                                .platformKeyboardType(.decimalPad)
                        case .subtotal:
                            FormField(text: $subtotal, placeholder: "0.00")
                                .platformKeyboardType(.decimalPad)
                        }
                    }
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

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Notes")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    FormField(text: $notes, placeholder: "Notes", axis: .vertical)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Email Receipt")
                        .font(Typography.label)
                        .foregroundStyle(BrandColors.textSecondary)
                    HStack(spacing: Spacing.xs) {
                        horizontalOptionCard(selection: $hasEmailReceipt, value: true, label: "Yes")
                        horizontalOptionCard(selection: $hasEmailReceipt, value: false, label: "No")
                    }
                }

                MediaGallerySection(
                    title: "Receipts",
                    attachments: receiptImages,
                    onUploadAttachmentFile: { upload in
                        try await uploadReceiptImage(upload)
                    },
                    onUploadDocument: { data, fileName in
                        try await uploadReceiptPDF(data, fileName: fileName)
                    },
                    onRemoveAttachment: { attachment in
                        removeReceiptImage(attachment)
                    },
                    onSetPrimary: { attachment in
                        setReceiptPrimary(attachment)
                    }
                )
            }
        }
    }

    // MARK: - Receipt uploads

    private func ensurePendingTransactionId() -> String? {
        if let pendingTransactionId { return pendingTransactionId }
        guard let accountId = accountContext.currentAccountId else { return nil }
        let id = TransactionsService().newTransactionId(accountId: accountId)
        pendingTransactionId = id
        return id
    }

    private func uploadReceiptImage(_ upload: AttachmentUpload) async throws {
        guard let accountId = accountContext.currentAccountId,
              let txId = ensurePendingTransactionId() else { return }
        let filename = upload.storageFileName
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: txId,
            filename: filename
        )
        let url = try await mediaService.uploadData(upload.data, path: path, contentType: upload.contentType)
        let thumbnails = await mediaService.uploadThumbnails(
            for: upload.data,
            originalPath: path,
            contentType: upload.contentType
        )
        let isPrimary = receiptImages.isEmpty
        receiptImages.append(AttachmentRef(
            url: url,
            thumbnailUrlSm: thumbnails.sm,
            thumbnailUrlMd: thumbnails.md,
            fileName: upload.displayFileName,
            contentType: upload.contentType,
            isPrimary: isPrimary
        ))
    }

    private func uploadReceiptPDF(_ data: Data, fileName: String) async throws {
        guard let accountId = accountContext.currentAccountId,
              let txId = ensurePendingTransactionId() else { return }
        let storageFileName = "\(UUID().uuidString).pdf"
        let path = mediaService.uploadPath(
            accountId: accountId,
            entityType: "transactions",
            entityId: txId,
            filename: storageFileName
        )
        let url = try await mediaService.uploadData(data, path: path, contentType: "application/pdf")
        let isPrimary = receiptImages.isEmpty
        receiptImages.append(AttachmentRef(
            url: url,
            kind: .pdf,
            fileName: fileName,
            contentType: "application/pdf",
            isPrimary: isPrimary
        ))
    }

    private func removeReceiptImage(_ attachment: AttachmentRef) {
        receiptImages.removeAll { $0.url == attachment.url }
        Task { try? await mediaService.deleteImage(url: attachment.url) }
    }

    private func setReceiptPrimary(_ attachment: AttachmentRef) {
        receiptImages = receiptImages.map { img in
            var copy = img
            copy.isPrimary = (img.url == attachment.url)
            return copy
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

    // MARK: - Horizontal Option Card

    @ViewBuilder
    private func horizontalOptionCard<T: Hashable>(selection: Binding<T>, value: T, label: String) -> some View {
        let isSelected = selection.wrappedValue == value
        Button {
            selection.wrappedValue = value
        } label: {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .strokeBorder(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(BrandColors.primary)
                                .frame(width: 8, height: 8)
                        }
                    }
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                    .stroke(isSelected ? BrandColors.primary : BrandColors.border, lineWidth: Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
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
        let trimmedSource = effectiveSource.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.source = trimmedSource.isEmpty || transactionType == .paymentToBusiness ? nil : trimmedSource
        if let transactionDate {
            transaction.transactionDate = dateFormatter.string(from: transactionDate)
        }
        transaction.amountCents = parseCents(amount)
        transaction.purchasedBy = transactionType == .purchase ? purchasedBy : nil
        transaction.reimbursementType = resolvedReimbursementType
        transaction.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.hasEmailReceipt = hasEmailReceipt
        if !receiptImages.isEmpty {
            transaction.receiptImages = receiptImages
        }

        transaction.budgetCategoryId = routeThroughInventory ? nil : selectedCategoryId
        if isItemizedCategory {
            let amountCents = transaction.amountCents ?? 0
            switch taxMode {
            case .none:
                transaction.subtotalCents = amountCents
                transaction.taxRatePct = 0
            case .rate:
                let rate = Double(taxRate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                transaction.taxRatePct = rate
                // subtotal = amount / (1 + rate/100)
                let divisor = 1 + rate / 100
                transaction.subtotalCents = divisor > 0 ? Int((Double(amountCents) / divisor).rounded()) : amountCents
            case .subtotal:
                let subtotalCents = parseCents(subtotal) ?? 0
                transaction.subtotalCents = subtotalCents
                // rate = (amount - subtotal) / subtotal * 100
                transaction.taxRatePct = subtotalCents > 0
                    ? (Double(amountCents - subtotalCents) / Double(subtotalCents)) * 100
                    : 0
            }
        }
        if routeThroughInventory {
            transaction.projectId = nil
        }

        do {
            let txId: String
            if let pendingTransactionId {
                // A receipt upload allocated an ID — write the doc at that ID
                // so the storage path matches.
                try transactionsService.createTransaction(
                    accountId: accountId,
                    id: pendingTransactionId,
                    transaction: transaction
                )
                txId = pendingTransactionId
            } else {
                txId = try transactionsService.createTransaction(accountId: accountId, transaction: transaction)
            }
            if shouldSaveOtherVendorAsPreset {
                Task {
                    try? await vendorDefaultsService.addVendorIfMissing(
                        accountId: accountId,
                        name: effectiveSource
                    )
                }
            }
            submissionError = nil
            if routeThroughInventory {
                createdTransactionId = txId
            } else {
                transaction.id = txId
                onCreated?(transaction)
                dismiss()
            }
        } catch {
            submissionError = "Couldn't save the transaction: \(error.localizedDescription)"
        }
    }

    private var shouldSaveOtherVendorAsPreset: Bool {
        otherVendorMode
            && saveOtherVendorAsPreset
            && !otherVendorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Narrow-semantic reimbursement derivation:
    /// - Purchase with the "needs reimbursement" toggle on → direction inferred
    ///   from who paid (client-paid → owed-to-client; business-paid → owed-to-company).
    /// - Everything else → nil. Returns, Sales, payment collection, toggle-off all
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
