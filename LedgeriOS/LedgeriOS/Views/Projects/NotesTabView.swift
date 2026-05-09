import SwiftUI

struct NotesTabView: View {
    @Environment(ProjectContext.self) private var projectContext
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager

    @State private var noteText = ""
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
            SelectableNoteText(text: note.text, style: .body)

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
            try await projectContext.addNote(
                accountId: accountId,
                projectId: projectId,
                text: trimmed,
                source: "text",
                userId: userId,
                userName: userName
            )
        }
    }

    // MARK: - Helpers

    private func sourceIcon(_ source: String) -> String {
        switch source {
        case "voice": return "mic.fill"
        case "mcp": return "cpu"
        default: return "keyboard"
        }
    }
}
