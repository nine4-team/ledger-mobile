import LedgerTargetAppModel
import LedgerTargetCore
import SwiftUI

/// Thin binding of the existing list/form to the shared category command path.
struct TargetCategoryManagementView: View {
    private struct Row: Identifiable {
        let value: BudgetCategoryDefinitionSnapshot
        var id: BudgetCategoryID { value.id }
    }

    @State private var session: CategoryManagementSession
    @State private var showingCreate = false
    @State private var creationId = UUID()
    @State private var editing: Row?
    @State private var archiving: Row?
    @State private var actionError: String?

    init(accountId: AccountID, runtime: CategoryManagementRuntime) {
        _session = State(initialValue: CategoryManagementSession(accountId: accountId, runtime: runtime))
    }

    private var active: [Row] {
        session.categories.filter { !$0.isSystem && $0.lifecycle == .active }.map(Row.init)
    }
    private var archived: [Row] {
        session.categories.filter { !$0.isSystem && $0.lifecycle == .archived }.map(Row.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = actionError ?? session.syncMessage ?? session.message {
                Text(message).font(.caption).padding()
                    .accessibilityIdentifier("target-category-status")
            }
            if session.snapshot == nil {
                ProgressView("Loading categories")
            } else if !session.canSave && !session.isSaving {
                Text("Download the category directory before making changes.")
                    .font(.caption).padding()
            }
            CategoryManagementListPresentation(activeCategories: active, archivedCategories: archived,
                name: { $0.value.name.rawValue }, typeLabel: { $0.value.kind.rawValue.capitalized },
                onCreate: { creationId = UUID(); showingCreate = true }, onEdit: { editing = $0 },
                onArchive: { archiving = $0 }, onRestore: { changeLifecycle($0, action: .restore) },
                onMove: move)
                .disabled(!session.canSave)
        }
        .navigationTitle("Budget Categories")
        .task { await session.observe() }
        .onDisappear { session.invalidate() }
        .onChange(of: session.categories) { _, rows in
            // Do not leave a cached Fee definition visible after the reader
            // learns that this principal no longer has access to it.
            let visible = Set(rows.map(\.id))
            if let row = editing, !visible.contains(row.id) { editing = nil }
            if let row = archiving, !visible.contains(row.id) { archiving = nil }
        }
        .adaptivePresentation(isPresented: $showingCreate, style: .form) {
            CategoryFormPresentation(mode: .create, existingNames: session.categories.map(\.name.rawValue)) {
                name, kind, excluded in
                _ = try await session.save(.init(action: .create,
                    categoryId: BudgetCategoryID(validating: creationId.uuidString.lowercased()),
                    name: BudgetCategoryName(validating: name), kind: kind.categoryKind,
                    excludesFromOverallBudget: excluded))
            }
        }
        .adaptivePresentation(item: $editing, style: .form) { row in
            CategoryFormPresentation(mode: .edit(name: row.value.name.rawValue,
                kind: .init(row.value.kind), excluded: row.value.excludesFromOverallBudget),
                existingNames: session.categories.filter { $0.id != row.id }.map(\.name.rawValue)) {
                name, kind, excluded in
                _ = try await session.save(.init(action: .edit, categoryId: row.id,
                    expectedRevision: row.value.revision, name: BudgetCategoryName(validating: name),
                    kind: kind.categoryKind, excludesFromOverallBudget: excluded))
            }
        }
        .confirmationDialog("Archive this category?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                if let row = archiving { changeLifecycle(row, action: .archive) }
                archiving = nil
            }
        } message: { Text("Transactions using it will still show it in reports.") }
    }

    private func changeLifecycle(_ row: Row, action: CategoryManagementPayload.Action) {
        save(.init(action: action, categoryId: row.id, expectedRevision: row.value.revision))
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var rows = active
        rows.move(fromOffsets: offsets, toOffset: destination)
        save(.init(action: .reorder, order: rows.map {
            CategoryOrderEntry(categoryId: $0.id, expectedRevision: $0.value.revision)
        }))
    }

    private func save(_ payload: CategoryManagementPayload) {
        actionError = nil
        Task { @MainActor in
            do { _ = try await session.save(payload) }
            catch { actionError = "The category change could not be saved. Please try again." }
        }
    }

}
