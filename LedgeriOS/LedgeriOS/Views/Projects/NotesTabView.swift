import SwiftUI

struct NotesTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var noteText = ""
    @State private var editingNote: ProjectNote?
    @State private var notePendingDelete: ProjectNote?
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

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
            .adaptivePresentation(item: $editingNote, style: .form) { note in
                EditNotesModal(notes: note.text) { newText in
                    updateNote(note, text: newText)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                SelectableNoteText(text: note.text, style: .body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if note.id != nil {
                    Menu {
                        Button {
                            editingNote = note
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            notePendingDelete = note
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(BrandColors.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Spacing.sm) {
                Image(systemName: sourceIcon(note.source))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                if !note.createdByName.isEmpty {
                    Text(note.createdByName)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                if let date = note.createdAt {
                    Text(date, style: .relative)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Add a note...", text: $noteText, axis: .vertical)
                .font(Typography.body)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(BrandColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )

            Button {
                sendNote()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? BrandColors.textTertiary
                        : BrandColors.primary)
            }
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(.bar)
    }

    // MARK: - Actions

    private func sendNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else { return }
        let userId = authManager.currentUser?.uid
        let userName = accountContext.member?.name
        noteText = ""
        Task {
            do {
                try await projectContext.addNote(
                    accountId: accountId,
                    projectId: projectId,
                    text: trimmed,
                    source: "text",
                    userId: userId,
                    userName: userName
                )
            } catch {
                noteText = trimmed
                errorMessage = "Failed to add note. Please try again."
            }
        }
    }

    private func updateNote(_ note: ProjectNote, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let noteId = note.id,
              let accountId = accountContext.currentAccountId,
              let projectId = projectContext.currentProjectId else { return }

        Task {
            do {
                try await projectContext.updateNote(
                    accountId: accountId,
                    projectId: projectId,
                    noteId: noteId,
                    text: trimmed
                )
            } catch {
                errorMessage = "Failed to update note. Please try again."
            }
        }
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

    private func sourceIcon(_ source: String) -> String {
        switch source {
        case "voice": return "mic.fill"
        case "mcp": return "cpu"
        default: return "keyboard"
        }
    }
}
