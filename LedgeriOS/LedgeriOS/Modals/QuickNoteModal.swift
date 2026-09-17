import SwiftUI

/// Project selection around the same editor used by project and space notes.
struct QuickNoteModal: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(ProjectContext.self) private var projectContext
    @State private var selectedProject: Project?
    @State private var showProjectPicker = false

    private var project: Project? { selectedProject ?? projectContext.project }

    var body: some View {
        NoteEditor(
            scope: project?.id.map(NoteScope.project),
            photos: accountContext.allSpaces.filter { $0.projectId == project?.id }.flatMap { $0.images ?? [] },
            header: AnyView(projectField),
            onSave: save
        )
        .adaptivePresentation(isPresented: $showProjectPicker, style: .picker) {
            ProjectPickerList { project in
                selectedProject = project
                showProjectPicker = false
            }
        }
    }

    private var projectField: some View {
        Button { showProjectPicker = true } label: {
            HStack {
                Text(project?.name ?? "Select Project")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .formInputStyle()
        }
        .buttonStyle(.plain)
    }

    private func save(_ text: String, _ reference: NoteVisualReference?) async throws {
        guard let projectId = project?.id,
              let accountId = accountContext.currentAccountId else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try await projectContext.addNote(
            accountId: accountId, projectId: projectId, text: text, source: "text",
            userId: authManager.currentUser?.uid, userName: accountContext.member?.name,
            visualReference: reference
        )
    }
}
