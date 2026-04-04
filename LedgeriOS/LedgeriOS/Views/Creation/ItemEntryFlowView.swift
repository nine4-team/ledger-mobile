import SwiftUI

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
        FormSheet(
            title: "Add Items",
            description: "Add items to this transaction. Items will be created in inventory.",
            primaryAction: FormSheetAction(
                title: transactionItems.isEmpty ? "Skip" : "Next"
            ) {
                currentStep = .sellPrompt
            },
            secondaryAction: FormSheetAction(title: "Done") {
                dismiss()
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
                    .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                            .stroke(BrandColors.primary, lineWidth: Dimensions.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 2: Sell Prompt

    private var sellPromptStep: some View {
        FormSheet(
            title: "Sell to Project?",
            description: "Items are in inventory. Would you like to sell them to a project now?",
            primaryAction: FormSheetAction(title: "Keep in Inventory") {
                dismiss()
            },
            secondaryAction: FormSheetAction(title: "Back") {
                currentStep = .addItems
            }
        ) {
            VStack(spacing: Spacing.md) {
                if let error = errorMessage {
                    Text(error)
                        .font(Typography.small)
                        .foregroundStyle(StatusColors.missedText)
                }

                sellOptionCard(
                    "Sell All to a Project",
                    icon: "arrow.right.circle",
                    description: "\(transactionItems.count) \(transactionItems.count == 1 ? "item" : "items") will be sold"
                ) {
                    selectedItemIds = Set(transactionItems.compactMap(\.id))
                    showProjectPicker = true
                }

                if transactionItems.count > 1 {
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

    // MARK: - Select Items Step

    private var selectItemsStep: some View {
        FormSheet(
            title: "Select Items",
            description: "Choose items to sell to a project.",
            primaryAction: FormSheetAction(
                title: "Next",
                isDisabled: selectedItemIds.isEmpty
            ) {
                showProjectPicker = true
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

        Task {
            do {
                try await service.sellToProject(
                    items: itemsToSell,
                    destinationProjectId: projectId,
                    accountId: accountId,
                    userId: authManager.currentUser?.uid,
                    destinationCategoryId: budgetCategoryId
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
