import SwiftUI

struct NotesTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var showingNewNote = false
    @State private var viewingNote: LedgerNote?
    @State private var editingNote: ProjectNote?
    @State private var notePendingDelete: ProjectNote?
    @State private var errorMessage: String?

    // MARK: - Computed

    private var sortedNotes: [ProjectNote] {
        projectContext.notes.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
    }

    private var legacyNotes: String? {
        guard let text = projectContext.project?.notes, !text.isEmpty else { return nil }
        return text
    }

    private var hasContent: Bool {
        !sortedNotes.isEmpty || legacyNotes != nil
    }

    // MARK: - Body

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .adaptivePresentation(isPresented: $showingNewNote, style: .form) {
                NoteEditor(scope: noteScope, photos: availablePhotos, onSave: addNote)
            }
            .adaptivePresentation(item: $editingNote, style: .form) { note in
                NoteEditor(scope: noteScope, photos: availablePhotos, note: note) { text, reference in
                    try await updateNote(note, text: text, reference: reference)
                }
            }
            .adaptivePresentation(item: $viewingNote, style: .viewer) { note in
                if let reference = note.visualReference {
                    NoteReferenceViewer(reference: reference, noteText: note.text)
                }
            }
            .confirmationDialog("Delete Note?", isPresented: deleteConfirmationBinding) {
                Button("Delete", role: .destructive) {
                    deletePendingNote()
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Error", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if hasContent {
            ScrollView {
                LazyVStack(spacing: Spacing.cardListGap) {
                    if let legacy = legacyNotes {
                        legacyCard(legacy)
                    }
                    ForEach(sortedNotes) { note in
                        noteCard(note)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sm)
            }
        } else {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Add notes to track project details")
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Note Card

    private func noteCard(_ note: ProjectNote) -> some View {
        NoteCard(note: note, onEdit: { editingNote = note },
                 onDelete: { notePendingDelete = note }, onViewPhoto: { viewingNote = note })
    }

    // MARK: - Legacy Card

    private func legacyCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Legacy Notes")
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textTertiary)
            SelectableNoteText(text: text, style: .small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .background(BrandColors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
    }

    // MARK: - Input Bar

    private var noteScope: NoteScope? {
        projectContext.currentProjectId.map(NoteScope.project)
    }

    private var availablePhotos: [AttachmentRef] {
        NotePhotoCatalog.availableImages(projectContext.spaces.flatMap { $0.images ?? [] })
    }

    private var inputBar: some View {
        Button { showingNewNote = true } label: {
            Label("Add note", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(.bar)
    }

    private func addNote(_ text: String, _ reference: NoteVisualReference?) async throws {
        guard let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else { throw ProjectNoteEditError.missingContext }
        try await projectContext.addNote(
            accountId: accountId, projectId: projectId, text: text, source: "text",
            userId: authManager.currentUser?.uid, userName: accountContext.member?.name,
            visualReference: reference
        )
    }

    private func updateNote(_ note: ProjectNote, text: String, reference: NoteVisualReference?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || reference != nil),
              let noteId = note.id,
              let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else {
            throw ProjectNoteEditError.missingContext
        }

        try await projectContext.updateNote(
            accountId: accountId,
            projectId: projectId,
            noteId: noteId,
            text: trimmed,
            visualReference: reference
        )
    }

    private func deletePendingNote() {
        guard let note = notePendingDelete,
              let noteId = note.id,
              let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else {
            notePendingDelete = nil
            return
        }

        notePendingDelete = nil
        Task {
            do {
                try await projectContext.deleteNote(
                    accountId: accountId,
                    projectId: projectId,
                    noteId: noteId
                )
            } catch {
                errorMessage = "Failed to delete note. Please try again."
            }
        }
    }

    // MARK: - Helpers

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { notePendingDelete != nil },
            set: { if !$0 { notePendingDelete = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

}

private enum ProjectNoteEditError: Error {
    case missingContext
}
