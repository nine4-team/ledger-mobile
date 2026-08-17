import SwiftUI

enum ItemEntryFlowFooterStrategy: Equatable {
    case dismiss
    case continueToDestination
    case addAllToOriginProject
    case keepInInventory
}

enum ItemEntryFlowFooterResolver {
    static func addItems(itemCount: Int) -> ItemEntryFlowFooterStrategy {
        itemCount == 0 ? .dismiss : .continueToDestination
    }

    static func sellPrompt(originProjectId: String?) -> ItemEntryFlowFooterStrategy {
        originProjectId == nil ? .keepInInventory : .addAllToOriginProject
    }
}

/// Post-transaction flow for itemized categories.
/// After creating an inventory transaction, guides the user through:
/// 1. Adding items to the transaction
/// 2. Optionally selling items to a project
struct ItemEntryFlowView: View {
    let transactionId: String
    let budgetCategoryId: String?
    /// The project the user was in when they started — used as default sell target.
    let originProjectId: String?

    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    enum FlowStep {
        case addItems
        case sellPrompt
        case selectItems
    }

    @State private var currentStep: FlowStep = .addItems
    @State private var showNewItem = false
    @State private var selectedItemIds: Set<String> = []
    @State private var showProjectPicker = false
    @State private var destinationProject: Project?
    @State private var showConfirmation = false
    @State private var isSelling = false
    @State private var errorMessage: String?

    private var transactionItems: [Item] {
        accountContext.allItems.filter { $0.transactionId == transactionId }
    }

    /// The project the transaction was started from, if any. When present this is
    /// the obvious sell target — the user came from there and almost always wants
    /// the items to land there.
    private var originProject: Project? {
        guard let originProjectId else { return nil }
        return accountContext.allProjects.first { $0.id == originProjectId }
    }

    /// Routes the current `selectedItemIds` to the sell flow. When we know the
    /// origin project the user came from, skip the picker and confirm directly;
    /// otherwise show the picker so they can choose.
    private func proceedToSellTarget() {
        if let origin = originProject {
            destinationProject = origin
            showConfirmation = true
        } else {
            showProjectPicker = true
        }
    }

    private func sellAllToOriginProject() {
        selectedItemIds = Set(transactionItems.compactMap(\.id))
        proceedToSellTarget()
    }

    var body: some View {
        Group {
            switch currentStep {
            case .addItems:
                addItemsStep
            case .sellPrompt:
                sellPromptStep
            case .selectItems:
                selectItemsStep
            }
        }
        .adaptivePresentation(isPresented: $showNewItem, style: .form) {
            NewItemView(context: .inventory, initialTransactionId: transactionId)
        }
        .adaptivePresentation(isPresented: $showProjectPicker, style: .picker) {
            ProjectPickerList { project in
                destinationProject = project
                showProjectPicker = false
                showConfirmation = true
            }
        }
        .alert("Confirm Sale", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sell") { performSale() }
        } message: {
            let count = selectedItemIds.isEmpty ? transactionItems.count : selectedItemIds.count
            Text("Sell \(count) \(count == 1 ? "item" : "items") to \(destinationProject?.name ?? "project")?")
        }
    }

    // MARK: - Step 1: Add Items

    private var addItemsStep: some View {
        let footerStrategy = ItemEntryFlowFooterResolver.addItems(itemCount: transactionItems.count)
        return FormSheet(
            title: "Add Items",
            description: "Add items to this transaction. Items will be created in inventory.",
            primaryAction: FormSheetAction(
                title: footerStrategy == .dismiss ? "Done" : "Next"
            ) {
                if footerStrategy == .dismiss {
                    dismiss()
                } else {
                    currentStep = .sellPrompt
                }
            }
        ) {
            VStack(spacing: Spacing.md) {
                if !transactionItems.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("\(transactionItems.count) \(transactionItems.count == 1 ? "item" : "items") added")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)

                        ForEach(transactionItems) { item in
                            itemRow(item)
                        }
                    }
                }

                Button { showNewItem = true } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Item")
                    }
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                            .strokeBorder(BrandColors.primary, lineWidth: Dimensions.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 2: Sell Prompt

    private var sellPromptStep: some View {
        let footerStrategy = ItemEntryFlowFooterResolver.sellPrompt(originProjectId: originProjectId)
        return FormSheet(
            title: "Sell to Project?",
            description: "Items are in inventory. Would you like to sell them to a project now?",
            primaryAction: FormSheetAction(
                title: footerStrategy == .addAllToOriginProject
                    ? "Add All to \(originProject?.name ?? "Project")"
                    : "Keep in Inventory"
            ) {
                if footerStrategy == .addAllToOriginProject {
                    sellAllToOriginProject()
                } else {
                    dismiss()
                }
            },
            secondaryAction: footerStrategy == .addAllToOriginProject
                ? FormSheetAction(title: "Keep in Inventory") { dismiss() }
                : FormSheetAction(title: "Back") { currentStep = .addItems }
        ) {
            VStack(spacing: Spacing.md) {
                if let error = errorMessage {
                    Text(error)
                        .font(Typography.small)
                        .foregroundStyle(StatusColors.missedText)
                }

                let itemCount = transactionItems.count
                let itemNoun = itemCount == 1 ? "item" : "items"

                if itemCount == 0 {
                    Text("No items have been added yet.")
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                } else {
                    if originProject == nil {
                        sellOptionCard(
                            "Sell All to a Project",
                            icon: "arrow.right.circle",
                            description: "\(itemCount) \(itemNoun) will be sold"
                        ) {
                            selectedItemIds = Set(transactionItems.compactMap(\.id))
                            proceedToSellTarget()
                        }
                    }

                    if originProject != nil {
                        sellOptionCard(
                            "Sell to a Different Project",
                            icon: "arrow.triangle.branch",
                            description: "Pick another project for these \(itemNoun)"
                        ) {
                            selectedItemIds = Set(transactionItems.compactMap(\.id))
                            showProjectPicker = true
                        }
                    }

                    if itemCount > 1 {
                        sellOptionCard(
                            "Select Items to Sell",
                            icon: "checklist",
                            description: "Choose which items to sell to a project"
                        ) {
                            selectedItemIds = []
                            currentStep = .selectItems
                        }
                    }
                }
            }
        }
    }

    // MARK: - Select Items Step

    private var selectItemsStep: some View {
        FormSheet(
            title: "Select Items",
            description: "Choose items to sell to a project.",
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: selectedItemIds.isEmpty
            ) {
                proceedToSellTarget()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                selectedItemIds = []
                currentStep = .sellPrompt
            }
        ) {
            VStack(spacing: Spacing.sm) {
                ForEach(transactionItems) { item in
                    if let itemId = item.id {
                        Button {
                            if selectedItemIds.contains(itemId) {
                                selectedItemIds.remove(itemId)
                            } else {
                                selectedItemIds.insert(itemId)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedItemIds.contains(itemId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedItemIds.contains(itemId) ? BrandColors.primary : BrandColors.textSecondary)
                                Text(item.name ?? "Untitled")
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Spacer()
                                if let cents = item.purchasePriceCents {
                                    Text(CurrencyFormatting.formatCentsWithDecimals(cents))
                                        .font(Typography.body)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                            }
                            .padding(Spacing.sm)
                            .contentShape(Rectangle())
                            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                                    .stroke(
                                        selectedItemIds.contains(itemId) ? BrandColors.primary : BrandColors.border,
                                        lineWidth: Dimensions.borderWidth
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private func itemRow(_ item: Item) -> some View {
        HStack {
            Image(systemName: "shippingbox")
                .foregroundStyle(BrandColors.textSecondary)
            Text(item.name ?? "Untitled")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
            Spacer()
            if let cents = item.purchasePriceCents {
                Text(CurrencyFormatting.formatCentsWithDecimals(cents))
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .padding(Spacing.sm)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    private func sellOptionCard(_ title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(BrandColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(description)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }

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

    // MARK: - Sell Action

    private func performSale() {
        guard let project = destinationProject,
              let projectId = project.id,
              let accountId = accountContext.currentAccountId else { return }

        isSelling = true
        errorMessage = nil

        let itemsToSell = transactionItems.filter { selectedItemIds.contains($0.id ?? "") }
        guard !itemsToSell.isEmpty else {
            errorMessage = "No items selected."
            isSelling = false
            return
        }

        let service = InventoryOperationsService()
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)

        Task {
            do {
                try await service.sellToProject(
                    items: itemsToSell,
                    destinationProjectId: projectId,
                    budgetCategoryId: budgetCategoryId ?? "uncategorized",
                    accountId: accountId,
                    inventoryLabel: inventoryLabel,
                    userId: authManager.currentUser?.uid,
                    resolveInventoryIntentTransactionId: itemsToSell.count == transactionItems.count
                        ? transactionId
                        : nil
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to complete sale. Please try again."
                    isSelling = false
                }
            }
        }
    }
}
