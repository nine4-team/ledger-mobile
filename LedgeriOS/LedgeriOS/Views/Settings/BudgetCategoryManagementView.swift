import SwiftUI
import FirebaseFirestore

struct BudgetCategoryManagementView: View {
    @Environment(AccountContext.self) private var accountContext

    @State private var categories: [BudgetCategory] = []
    @State private var listener: ListenerRegistration?
    @State private var showingCreateSheet = false
    @State private var editingCategory: BudgetCategory?
    @State private var archiveTarget: BudgetCategory?

    private let service = BudgetCategoriesService(syncTracker: NoOpSyncTracker())

    private var activeCategories: [BudgetCategory] {
        categories
            .filter { $0.isArchived != true }
            .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
    }

    private var archivedCategories: [BudgetCategory] {
        categories.filter { $0.isArchived == true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Add button
                Button {
                    showingCreateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Category")
                    }
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.primary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.sm)

                // Active categories
                if activeCategories.isEmpty {
                    Text("No categories yet. Add one to get started.")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .padding(.horizontal, Spacing.screenPadding)
                } else {
                    List {
                        ForEach(activeCategories) { category in
                            CategoryManagementRow(
                                category: category,
                                onEdit: { editingCategory = category },
                                onArchive: { archiveTarget = category }
                            )
                            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.screenPadding, bottom: Spacing.xs, trailing: Spacing.screenPadding))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveCategories)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                    .frame(minHeight: CGFloat(activeCategories.count) * 72)
                }

                // Archived section
                if !archivedCategories.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Archived")
                            .sectionLabelStyle()
                            .padding(.horizontal, Spacing.screenPadding)

                        LazyVStack(spacing: Spacing.cardListGap) {
                            ForEach(archivedCategories) { category in
                                ArchivedCategoryRow(category: category) {
                                    unarchiveCategory(category)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(BrandColors.background)
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
        .sheet(isPresented: $showingCreateSheet) {
            CategoryFormModal(mode: .create) { name, categoryType, excludeFromBudget in
                createCategory(name: name, categoryType: categoryType, excludeFromBudget: excludeFromBudget)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingCategory) { category in
            CategoryFormModal(mode: .edit(category)) { name, categoryType, excludeFromBudget in
                updateCategory(category, name: name, categoryType: categoryType, excludeFromBudget: excludeFromBudget)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Archive this category?",
            isPresented: Binding(
                get: { archiveTarget != nil },
                set: { if !$0 { archiveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                if let target = archiveTarget {
                    archiveCategory(target)
                    archiveTarget = nil
                }
            }
        } message: {
            Text("Transactions using it will still show it in reports.")
        }
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }
        listener = service.subscribeToBudgetCategories(accountId: accountId) { categories in
            self.categories = categories
        }
    }

    private func createCategory(name: String, categoryType: BudgetCategoryType, excludeFromBudget: Bool) {
        guard let accountId = accountContext.currentAccountId else { return }
        var category = BudgetCategory()
        category.accountId = accountId
        category.name = name
        category.slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        category.order = (activeCategories.last?.order ?? 0) + 1
        category.metadata = BudgetCategoryMetadata(
            categoryType: categoryType,
            excludeFromOverallBudget: excludeFromBudget
        )
        _ = try? service.createBudgetCategory(accountId: accountId, category: category)
    }

    private func updateCategory(_ category: BudgetCategory, name: String, categoryType: BudgetCategoryType, excludeFromBudget: Bool) {
        guard let accountId = accountContext.currentAccountId, let id = category.id else { return }
        let fields: [String: Any] = [
            "name": name,
            "slug": name.lowercased().replacingOccurrences(of: " ", with: "-"),
            "metadata": [
                "categoryType": categoryType.rawValue,
                "excludeFromOverallBudget": excludeFromBudget
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }

    private func archiveCategory(_ category: BudgetCategory) {
        guard let accountId = accountContext.currentAccountId, let id = category.id else { return }
        let fields: [String: Any] = ["isArchived": true, "updatedAt": FieldValue.serverTimestamp()]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        guard let accountId = accountContext.currentAccountId else { return }
        var reordered = activeCategories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            guard let id = category.id else { continue }
            let fields: [String: Any] = ["order": index, "updatedAt": FieldValue.serverTimestamp()]
            Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
        }
    }

    private func unarchiveCategory(_ category: BudgetCategory) {
        guard let accountId = accountContext.currentAccountId, let id = category.id else { return }
        let fields: [String: Any] = ["isArchived": false, "updatedAt": FieldValue.serverTimestamp()]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }
}

// MARK: - Category Row

private struct CategoryManagementRow: View {
    let category: BudgetCategory
    let onEdit: () -> Void
    let onArchive: () -> Void

    private var typePill: String {
        switch category.metadata?.categoryType {
        case .itemized: return "Itemized"
        case .fee: return "Fee"
        default: return "General"
        }
    }

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(category.name)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    Badge(text: typePill)
                }

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(BrandColors.primary)
                    }

                    Button { onArchive() } label: {
                        Image(systemName: "archivebox")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}

// MARK: - Archived Category Row

private struct ArchivedCategoryRow: View {
    let category: BudgetCategory
    let onUnarchive: () -> Void

    var body: some View {
        Card {
            HStack {
                Text(category.name)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                Button("Unarchive") { onUnarchive() }
                    .font(Typography.buttonSmall)
                    .foregroundStyle(BrandColors.primary)
            }
        }
    }
}
