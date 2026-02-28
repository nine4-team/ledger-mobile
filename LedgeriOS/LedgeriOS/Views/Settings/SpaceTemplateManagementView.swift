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
                    List {
                        ForEach(sortedTemplates) { template in
                            TemplateRow(
                                template: template,
                                onEdit: { editingTemplate = template },
                                onDelete: { deleteTarget = template }
                            )
                            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.screenPadding, bottom: Spacing.xs, trailing: Spacing.screenPadding))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove(perform: moveTemplates)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                    .frame(minHeight: CGFloat(sortedTemplates.count) * 72)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(BrandColors.background)
        .onAppear { startListening() }
        .onDisappear { listener?.remove() }
        .sheet(isPresented: $showingCreateSheet) {
            TemplateFormSheet(mode: .create) { name, notes, checklists in
                createTemplate(name: name, notes: notes, checklists: checklists)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateFormSheet(mode: .edit(template)) { name, notes, checklists in
                updateTemplate(template, name: name, notes: notes, checklists: checklists)
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

    private func createTemplate(name: String, notes: String?, checklists: [Checklist]) {
        guard let accountId = accountContext.currentAccountId else { return }
        var template = SpaceTemplate()
        template.name = name
        template.notes = notes
        template.checklists = checklists.isEmpty ? nil : checklists
        template.order = (sortedTemplates.last?.order ?? 0) + 1
        _ = try? service.create(accountId: accountId, template: template)
    }

    private func updateTemplate(_ template: SpaceTemplate, name: String, notes: String?, checklists: [Checklist]) {
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
        let checklistData = checklists.map { checklist in
            [
                "id": checklist.id,
                "name": checklist.name,
                "items": checklist.items.map { item in
                    ["id": item.id, "text": item.text, "isChecked": item.isChecked] as [String: Any]
                }
            ] as [String: Any]
        }
        fields["checklists"] = checklistData.isEmpty ? NSNull() : checklistData
        Task { try? await service.update(accountId: accountId, templateId: id, fields: fields) }
    }

    private func moveTemplates(from source: IndexSet, to destination: Int) {
        guard let accountId = accountContext.currentAccountId else { return }
        var reordered = sortedTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in reordered.enumerated() {
            guard let id = template.id else { continue }
            let fields: [String: Any] = ["order": index, "updatedAt": FieldValue.serverTimestamp()]
            Task { try? await service.update(accountId: accountId, templateId: id, fields: fields) }
        }
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
    let onSave: (String, String?, [Checklist]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var checklists: [Checklist]
    @State private var hasSubmitted = false

    init(mode: Mode, onSave: @escaping (String, String?, [Checklist]) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _notes = State(initialValue: "")
            _checklists = State(initialValue: [])
        case .edit(let template):
            _name = State(initialValue: template.name)
            _notes = State(initialValue: template.notes ?? "")
            _checklists = State(initialValue: template.checklists ?? [])
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

                // Checklists section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Checklists")
                            .font(Typography.label)
                            .foregroundStyle(BrandColors.textSecondary)

                        Spacer()

                        Button {
                            checklists.append(Checklist(name: "", items: []))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add")
                            }
                            .font(Typography.buttonSmall)
                            .foregroundStyle(BrandColors.primary)
                        }
                    }

                    if checklists.isEmpty {
                        Text("No checklists. Add one to include in this template.")
                            .font(Typography.small)
                            .foregroundStyle(BrandColors.textTertiary)
                    } else {
                        ForEach($checklists) { $checklist in
                            ChecklistEditor(checklist: $checklist) {
                                checklists.removeAll { $0.id == checklist.id }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleSave() {
        hasSubmitted = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Filter out empty checklists (no name and no items)
        let validChecklists = checklists.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || !$0.items.isEmpty }
        onSave(trimmed, notes.isEmpty ? nil : notes, validChecklists)
        dismiss()
    }
}

// MARK: - Checklist Editor

private struct ChecklistEditor: View {
    @Binding var checklist: Checklist
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                TextField("Checklist name", text: $checklist.name)
                    .font(Typography.body)
                    .textFieldStyle(.roundedBorder)

                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(BrandColors.destructive)
                        .font(Typography.small)
                }
                .buttonStyle(.plain)
            }

            ForEach($checklist.items) { $item in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "circle")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)

                    TextField("Item text", text: $item.text)
                        .font(Typography.small)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        checklist.items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BrandColors.textTertiary)
                            .font(Typography.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                checklist.items.append(ChecklistItem(text: ""))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Item")
                }
                .font(Typography.caption)
                .foregroundStyle(BrandColors.primary)
            }
        }
        .padding(Spacing.sm)
        .background(BrandColors.inputBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
    }
}
