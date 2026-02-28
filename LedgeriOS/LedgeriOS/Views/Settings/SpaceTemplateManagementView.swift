import SwiftUI
import FirebaseFirestore

struct SpaceTemplateManagementView: View {
    @Environment(AccountContext.self) private var accountContext

    @State private var templates: [SpaceTemplate] = []
    @State private var listener: ListenerRegistration?
    @State private var showingCreateSheet = false
    @State private var editingTemplate: SpaceTemplate?
    @State private var deleteTarget: SpaceTemplate?

    private let service = SpaceTemplatesService(syncTracker: NoOpSyncTracker())

    private var sortedTemplates: [SpaceTemplate] {
        templates
            .filter { $0.isArchived != true }
            .sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
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
                        Text("Add Template")
                    }
                    .font(Typography.button)
                    .foregroundStyle(BrandColors.primary)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.sm)

                if sortedTemplates.isEmpty {
                    Text("No templates yet. Create one or save from a space.")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                        .padding(.horizontal, Spacing.screenPadding)
                } else {
                    LazyVStack(spacing: Spacing.cardListGap) {
                        ForEach(sortedTemplates) { template in
                            TemplateRow(
                                template: template,
                                onEdit: { editingTemplate = template },
                                onDelete: { deleteTarget = template }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(BrandColors.background)
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
        .sheet(isPresented: $showingCreateSheet) {
            TemplateFormSheet(mode: .create) { name, notes in
                createTemplate(name: name, notes: notes)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateFormSheet(mode: .edit(template)) { name, notes in
                updateTemplate(template, name: name, notes: notes)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    deleteTemplate(target)
                    deleteTarget = nil
                }
            }
        }
    }

    // MARK: - Data

    private func startListening() {
        guard let accountId = accountContext.currentAccountId else { return }
        listener = service.subscribe(accountId: accountId) { templates in
            self.templates = templates
        }
    }

    private func createTemplate(name: String, notes: String?) {
        guard let accountId = accountContext.currentAccountId else { return }
        var template = SpaceTemplate()
        template.name = name
        template.notes = notes
        template.order = (sortedTemplates.last?.order ?? 0) + 1
        _ = try? service.create(accountId: accountId, template: template)
    }

    private func updateTemplate(_ template: SpaceTemplate, name: String, notes: String?) {
        guard let accountId = accountContext.currentAccountId, let id = template.id else { return }
        var fields: [String: Any] = [
            "name": name,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let notes {
            fields["notes"] = notes
        } else {
            fields["notes"] = NSNull()
        }
        Task { try? await service.update(accountId: accountId, templateId: id, fields: fields) }
    }

    private func deleteTemplate(_ template: SpaceTemplate) {
        guard let accountId = accountContext.currentAccountId, let id = template.id else { return }
        Task { try? await service.delete(accountId: accountId, templateId: id) }
    }
}

// MARK: - Template Row

private struct TemplateRow: View {
    let template: SpaceTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(template.name)
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textPrimary)
                    if let notes = template.notes, !notes.isEmpty {
                        Text(notes)
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(1)
                    }
                    if let checklists = template.checklists, !checklists.isEmpty {
                        Text("\(checklists.count) checklist\(checklists.count == 1 ? "" : "s")")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                Spacer()

                HStack(spacing: Spacing.md) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(BrandColors.primary)
                    }

                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(BrandColors.destructive)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}

// MARK: - Template Form Sheet

private struct TemplateFormSheet: View {
    enum Mode {
        case create
        case edit(SpaceTemplate)
    }

    let mode: Mode
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var hasSubmitted = false

    init(mode: Mode, onSave: @escaping (String, String?) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
        case .edit(let template):
            _name = State(initialValue: template.name)
            _notes = State(initialValue: template.notes ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        FormSheet(
            title: isEditing ? "Edit Template" : "New Template",
            primaryAction: FormSheetAction(
                title: isEditing ? "Save" : "Create",
                action: handleSave
            ),
            secondaryAction: FormSheetAction(
                title: "Cancel",
                action: { dismiss() }
            ),
            error: hasSubmitted && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
        ) {
            VStack(spacing: Spacing.lg) {
                FormField(
                    label: "Name",
                    text: $name,
                    placeholder: "Template name",
                    errorText: hasSubmitted && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Name is required" : nil
                )

                FormField(
                    label: "Notes",
                    text: $notes,
                    placeholder: "Optional notes",
                    axis: .vertical
                )
            }
        }
    }

    private func handleSave() {
        hasSubmitted = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, notes.isEmpty ? nil : notes)
        dismiss()
    }
}
