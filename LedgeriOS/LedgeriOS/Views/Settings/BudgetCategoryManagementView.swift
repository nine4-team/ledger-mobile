import SwiftUI
#if canImport(FirebaseFirestore)
import FirebaseFirestore

struct BudgetCategoryManagementView: View {
    @Environment(AccountContext.self) private var accountContext

    @State private var categories: [BudgetCategory] = []
    @State private var listener: ListenerRegistration?
    @State private var showingCreateSheet = false
    @State private var editingCategory: BudgetCategory?
    @State private var archiveTarget: BudgetCategory?

    private let service = BudgetCategoriesService()

    private var activeCategories: [BudgetCategory] {
        categories
            .filter { $0.isArchived != true && !$0.isSystemCategory }
            .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
    }

    private var archivedCategories: [BudgetCategory] {
        categories.filter { $0.isArchived == true && !$0.isSystemCategory }
    }

    var body: some View {
        CategoryManagementListPresentation(
            activeCategories: activeCategories,
            archivedCategories: archivedCategories,
            name: { $0.name },
            typeLabel: { CategoryDisplay.pillLabel(for: $0) },
            onCreate: { showingCreateSheet = true },
            onEdit: { editingCategory = $0 },
            onArchive: { archiveTarget = $0 },
            onRestore: unarchiveCategory,
            onMove: moveCategories
        )
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
        .adaptivePresentation(isPresented: $showingCreateSheet, style: .form) {
            CategoryFormModal(
                mode: .create,
                existingNames: activeCategories.map(\.name)
            ) { name, categoryType, excludeFromBudget in
                createCategory(name: name, categoryType: categoryType, excludeFromBudget: excludeFromBudget)
            }
        }
        .adaptivePresentation(item: $editingCategory, style: .form) { category in
            CategoryFormModal(
                mode: .edit(category),
                existingNames: activeCategories.filter { $0.id != category.id }.map(\.name)
            ) { name, categoryType, excludeFromBudget in
                updateCategory(category, name: name, categoryType: categoryType, excludeFromBudget: excludeFromBudget)
            }
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
        nonisolated(unsafe) let fields: [String: Any] = [
            "name": name,
            "slug": name.lowercased().replacingOccurrences(of: " ", with: "-"),
            "metadata.categoryType": categoryType.rawValue,
            "metadata.excludeFromOverallBudget": excludeFromBudget,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }

    private func archiveCategory(_ category: BudgetCategory) {
        guard let accountId = accountContext.currentAccountId, let id = category.id else { return }
        nonisolated(unsafe) let fields: [String: Any] = ["isArchived": true, "updatedAt": FieldValue.serverTimestamp()]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        guard let accountId = accountContext.currentAccountId else { return }
        var reordered = activeCategories
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            guard let id = category.id else { continue }
            nonisolated(unsafe) let fields: [String: Any] = ["order": index, "updatedAt": FieldValue.serverTimestamp()]
            Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
        }
    }

    private func unarchiveCategory(_ category: BudgetCategory) {
        guard let accountId = accountContext.currentAccountId, let id = category.id else { return }
        nonisolated(unsafe) let fields: [String: Any] = ["isArchived": false, "updatedAt": FieldValue.serverTimestamp()]
        Task { try? await service.updateBudgetCategory(accountId: accountId, categoryId: id, fields: fields) }
    }
}
#endif

/// The existing list, with data and actions supplied by its owning screen.
/// Neither category storage nor an operation queue belongs in presentation.
struct CategoryManagementListPresentation<Category: Identifiable>: View {
    let activeCategories: [Category]
    let archivedCategories: [Category]
    let name: (Category) -> String
    let typeLabel: (Category) -> String
    let onCreate: () -> Void
    let onEdit: (Category) -> Void
    let onArchive: (Category) -> Void
    let onRestore: (Category) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        ScrollView {
            AdaptiveContentWidth {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Button(action: onCreate) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Category")
                        }
                        .font(Typography.button)
                        .foregroundStyle(BrandColors.primary)
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.sm)

                    if activeCategories.isEmpty {
                        Text("No categories yet. Add one to get started.")
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textSecondary)
                            .padding(.horizontal, Spacing.screenPadding)
                    } else {
                        List {
                            ForEach(activeCategories) { category in
                                CategoryManagementRow(
                                    name: name(category), typePill: typeLabel(category),
                                    onEdit: { onEdit(category) },
                                    onArchive: { onArchive(category) }
                                )
                                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.screenPadding, bottom: Spacing.xs, trailing: Spacing.screenPadding))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .onMove(perform: onMove)
                        }
                        .listStyle(.plain)
                        #if canImport(UIKit)
                        .environment(\.editMode, .constant(.active))
                        #endif
                        .frame(minHeight: CGFloat(activeCategories.count) * 72)
                    }

                    if !archivedCategories.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Archived")
                                .sectionLabelStyle()
                                .padding(.horizontal, Spacing.screenPadding)

                            LazyVStack(spacing: Spacing.cardListGap) {
                                ForEach(archivedCategories) { category in
                                    ArchivedCategoryRow(name: name(category)) {
                                        onRestore(category)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                        }
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .background(BrandColors.background)
    }
}

// MARK: - Category Row

private struct CategoryManagementRow: View {
    let name: String
    let typePill: String
    let onEdit: () -> Void
    let onArchive: () -> Void

    var body: some View {
        Card {
            HStack {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(name)
                            .font(Typography.body)
                            .foregroundStyle(BrandColors.textPrimary)
                        Badge(text: typePill)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("category-name-\(name)")

                HStack(spacing: Spacing.md) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .accessibilityLabel("Edit \(name)")

                    Button { onArchive() } label: {
                        Image(systemName: "archivebox")
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                    .accessibilityLabel("Archive \(name)")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Archived Category Row

private struct ArchivedCategoryRow: View {
    let name: String
    let onUnarchive: () -> Void

    var body: some View {
        Card {
            HStack {
                Text(name)
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
