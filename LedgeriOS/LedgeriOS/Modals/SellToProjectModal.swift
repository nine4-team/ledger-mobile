import SwiftUI
import FirebaseFirestore

/// Entry point for financial cross-scope item flows.
/// Inventory items with proven source-project provenance return there directly;
/// other inventory items and project items use the normal sale destination flow.
struct SellItemsModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?

    private enum Destination {
        case project
        case inventory
    }

    private var canSellToInventory: Bool {
        !items.isEmpty
            && items.allSatisfy { $0.projectId != nil }
            && items.allSatisfy { !InventoryOperationsService.cameFromInventory($0) }
    }

    @Environment(AccountContext.self) private var accountContext

    private var returnDestination: (project: Project, provenance: ReturnToProjectProvenance)? {
        guard let provenance = InventoryOperationsService.returnToProjectProvenance(
            for: items,
            transactions: accountContext.allTransactions
        ), let project = accountContext.allProjects.first(where: { $0.id == provenance.projectId }) else {
            return nil
        }
        return (project, provenance)
    }

    var body: some View {
        Group {
            if let returnDestination {
                ReturnToProjectModal(
                    items: items,
                    accountId: accountId,
                    project: returnDestination.project,
                    initialProvenance: returnDestination.provenance,
                    onComplete: onComplete
                )
            } else {
                switch destination {
                case .project:
                    SellToProjectModal(items: items, accountId: accountId, onComplete: onComplete)
                case .inventory:
                    SellToInventoryModal(items: items, accountId: accountId, onComplete: onComplete)
                case nil:
                    destinationPicker
                }
            }
        }
    }

    private var destinationPicker: some View {
        FormSheet(
            title: "Sell",
            description: "Choose where these items are being sold.",
            primaryAction: FormSheetAction(title: "Cancel", action: { dismiss() })
        ) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                destinationButton(
                    title: "Project",
                    subtitle: "Create a sale into a project budget.",
                    icon: "folder",
                    action: { destination = .project }
                )

                if canSellToInventory {
                    destinationButton(
                        title: "Business Inventory",
                        subtitle: "Create a sale from the project into inventory.",
                        icon: "shippingbox",
                        action: { destination = .inventory }
                    )
                }
            }
        }
    }

    private func destinationButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(BrandColors.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(subtitle)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .padding(Spacing.md)
            .background(BrandColors.surfaceTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// A true reversal of the current project-to-inventory movement. Destination,
/// categories, and amounts are locked to the movement's recorded provenance.
struct ReturnToProjectModal: View {
    let items: [Item]
    let accountId: String
    let project: Project
    let initialProvenance: ReturnToProjectProvenance
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var categoryDescription: String {
        let categories = initialProvenance.categoryIds.compactMap { id in
            accountContext.allBudgetCategories.first(where: { $0.id == id })?.name
        }.sorted()
        if initialProvenance.categoryIds.count == 1 {
            return categories.first ?? "Original category"
        }
        return categories.count == initialProvenance.categoryIds.count
            ? categories.joined(separator: ", ")
            : "\(initialProvenance.categoryIds.count) original categories"
    }

    var body: some View {
        FormSheet(
            title: "Return to Project",
            description: "This reverses the inventory movement using its original project, budget category, and amount.",
            primaryAction: FormSheetAction(title: "Cancel", action: { dismiss() })
        ) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                summaryRow(label: "Project", value: project.name)
                summaryRow(label: "Budget Category", value: categoryDescription)
                summaryRow(
                    label: "Amount",
                    value: CurrencyFormatting.formatCentsWithDecimals(initialProvenance.amountCents)
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.small)
                        .foregroundStyle(StatusColors.missedText)
                }

                AppButton(
                    title: "Confirm Return",
                    isLoading: isSaving,
                    action: performReturn
                )
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(label)
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
            Spacer()
            Text(value)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(Spacing.md)
        .background(BrandColors.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performReturn() {
        guard !isSaving else { return }
        var liveItemsById: [String: Item] = [:]
        for item in accountContext.allItems {
            if let itemId = item.id { liveItemsById[itemId] = item }
        }
        let liveItems = items.compactMap { item in
            item.id.flatMap { liveItemsById[$0] }
        }
        guard liveItems.count == items.count else {
            errorMessage = "One or more items are no longer available. Close and try again."
            return
        }
        guard let liveProvenance = InventoryOperationsService.returnToProjectProvenance(
            for: liveItems,
            transactions: accountContext.allTransactions
        ), liveProvenance == initialProvenance,
           accountContext.allProjects.contains(where: { $0.id == liveProvenance.projectId }) else {
            errorMessage = "This item's return details changed. Close and try again."
            return
        }

        isSaving = true
        errorMessage = nil
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        Task {
            do {
                try await InventoryOperationsService().returnToProject(
                    items: liveItems,
                    provenance: liveProvenance,
                    accountId: accountId,
                    inventoryLabel: inventoryLabel,
                    userId: authManager.currentUser?.uid
                )
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

/// Project-destination sale flow.
/// Steps: (1) pick destination project, (2) pick budget category + confirm.
/// One category applies to the entire batch.
struct SellToProjectModal: View {
    let items: [Item]
    let accountId: String
    let onComplete: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(AccountContext.self) private var accountContext
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var destinationProject: Project?
    @State private var destinationCategoryId: String?
    @State private var projectPriceTexts: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Budget categories fetched independently for the destination project step.
    @State private var accountCategories: [BudgetCategory] = []
    @State private var categoriesListener: ListenerRegistration?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader

            switch step {
            case 1:
                step1DestinationProject
            case 2:
                step2ProjectPrices
            case 3:
                step2CategoryAndConfirm
            default:
                EmptyView()
            }
        }
        .onDisappear {
            categoriesListener?.remove()
            categoriesListener = nil
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack {
            if canGoBack {
                Button {
                    if step == 3 && missingProjectPriceItems.isEmpty {
                        step = 1
                    } else {
                        step -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(BrandColors.primary)
                }
                .buttonStyle(.plain)
            }

            Text(stepTitle)
                .font(Typography.h2)
                .foregroundStyle(BrandColors.textPrimary)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BrandColors.textTertiary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.screenPadding)
        .padding(.bottom, Spacing.md)
    }

    private var canGoBack: Bool {
        step > 1
    }

    private var stepTitle: String {
        switch step {
        case 1: return "Sell to Project"
        case 2: return "Project Price"
        case 3: return "Budget Category"
        default: return "Sell to Project"
        }
    }

    // MARK: - Step 1: Pick destination project

    private var step1DestinationProject: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("A sale record will be created for financial tracking. One budget category applies to all items in this batch.")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            ProjectPickerList { project in
                destinationProject = project
                loadAccountCategories()
                prepareProjectPricePrompts()
                step = missingProjectPriceItems.isEmpty ? 3 : 2
            }
        }
    }

    // MARK: - Step 2: Missing project prices

    private var step2ProjectPrices: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Set the project price for each item.")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            if let error = errorMessage {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(missingProjectPriceItems) { item in
                        FormField(
                            label: item.displayName.isEmpty ? "Item" : item.displayName,
                            text: Binding(
                                get: { projectPriceTexts[item.id ?? ""] ?? "" },
                                set: { projectPriceTexts[item.id ?? ""] = $0 }
                            ),
                            placeholder: "0.00",
                            helperText: item.sku
                        )
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
            }

            AppButton(title: "Continue") {
                guard validateProjectPrices() else { return }
                errorMessage = nil
                step = 3
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }

    // MARK: - Step 2: Category + confirm

    private var step2CategoryAndConfirm: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Select a budget category in \(destinationProject?.name ?? "destination project")")
                .font(Typography.small)
                .foregroundStyle(BrandColors.textSecondary)
                .padding(.horizontal, Spacing.screenPadding)

            if let error = errorMessage {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
                    .padding(.horizontal, Spacing.screenPadding)
            }

            CategoryPickerList(
                categories: accountCategories,
                selectedId: destinationCategoryId,
                onSelect: { category in
                    destinationCategoryId = category?.id
                },
                autoDismissOnSelect: false
            )

            Spacer()

            VStack(spacing: Spacing.sm) {
                AppButton(
                    title: "Confirm Sale",
                    isLoading: isSaving,
                    action: { performProjectMovement() }
                )
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.screenPadding)
        }
    }

    // MARK: - Action

    private func performProjectMovement() {
        guard let project = destinationProject, let projectId = project.id else { return }

        guard let categoryId = destinationCategoryId, !categoryId.isEmpty else {
            errorMessage = "Select a budget category for this sale."
            return
        }

        guard let pricedItems = itemsWithProjectPrices() else {
            errorMessage = "Enter a project price for each item."
            step = 2
            return
        }

        isSaving = true
        errorMessage = nil
        let service = InventoryOperationsService()
        let itemsToSell = pricedItems
        let acctId = accountId
        let inventoryLabel = InventoryOperationsService.inventoryLabel(for: accountContext.account?.name)
        let originsByItemId = InventoryOperationsService.originsByItemId(
            itemsToSell,
            transactions: accountContext.allTransactions
        )
        Task {
            do {
                if itemsToSell.allSatisfy({ $0.projectId == nil }) {
                    try await service.sellToProject(
                        items: itemsToSell,
                        destinationProjectId: projectId,
                        budgetCategoryId: categoryId,
                        accountId: acctId,
                        inventoryLabel: inventoryLabel,
                        userId: authManager.currentUser?.uid
                    )
                } else {
                    try await service.sellItemsFromProjectToProject(
                        items: itemsToSell,
                        destinationProjectId: projectId,
                        destinationCategoryId: categoryId,
                        accountId: acctId,
                        inventoryLabel: inventoryLabel,
                        userId: authManager.currentUser?.uid,
                        originsByItemId: originsByItemId
                    )
                }
                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

    private var missingProjectPriceItems: [Item] {
        items.filter {
            ($0.projectPriceCents ?? 0) <= 0 && ($0.purchasePriceCents ?? 0) <= 0
        }
    }

    private func prepareProjectPricePrompts() {
        for item in missingProjectPriceItems {
            guard let id = item.id else { continue }
            projectPriceTexts[id] = item.projectPriceCents.map { Self.centsToText($0) } ?? ""
        }
    }

    private func validateProjectPrices() -> Bool {
        for item in missingProjectPriceItems {
            guard let id = item.id,
                  let cents = Self.parseCents(projectPriceTexts[id]),
                  cents > 0 else {
                errorMessage = "Enter a valid project price for each item."
                return false
            }
        }
        return true
    }

    private func itemsWithProjectPrices() -> [Item]? {
        var result = items
        for index in result.indices {
            if let normalizedProjectPrice = result[index].normalizedProjectPriceCents,
               normalizedProjectPrice > 0 {
                result[index].projectPriceCents = normalizedProjectPrice
                continue
            }
            guard let id = result[index].id,
                  let cents = Self.parseCents(projectPriceTexts[id]),
                  cents > 0 else {
                return nil
            }
            result[index].projectPriceCents = cents
        }
        return result
    }

    private static func parseCents(_ text: String?) -> Int? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value > 0 else { return nil }
        let cents = NSDecimalNumber(decimal: value)
            .multiplying(by: 100)
            .rounding(accordingToBehavior: nil)
        return cents.intValue
    }

    private static func centsToText(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }

    private func loadAccountCategories() {
        categoriesListener?.remove()
        let service = BudgetCategoriesService()
        categoriesListener = service.subscribeToBudgetCategories(accountId: accountId) { categories in
            Task { @MainActor in
                accountCategories = categories
            }
        }
    }
}
