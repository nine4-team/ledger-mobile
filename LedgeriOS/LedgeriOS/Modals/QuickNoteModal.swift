import SwiftUI

struct QuickNoteModal: View {
    @Environment(AccountContext.self) private var accountContext
    @Environment(AuthManager.self) private var authManager
    @Environment(ProjectContext.self) private var projectContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedProject: Project?
    @State private var showProjectPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @FocusState private var isTextFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedProject != nil
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    projectField
                    noteField
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
            }
            .navigationTitle("Quick Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .adaptivePresentation(isPresented: $showProjectPicker, style: .picker) {
            ProjectPickerList { project in
                selectedProject = project
                showProjectPicker = false
            }
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            prefillProject()
            isTextFocused = true
        }
    }

    // MARK: - Subviews

    private var projectField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Project")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            Button { showProjectPicker = true } label: {
                HStack {
                    Text(selectedProject?.name ?? "Select Project")
                        .font(Typography.input)
                        .foregroundStyle(
                            selectedProject != nil
                                ? BrandColors.textPrimary
                                : BrandColors.textTertiary
                        )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .formInputStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Note")
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            TextField("What's on your mind?", text: $text, axis: .vertical)
                .font(Typography.input)
                .lineLimit(4...12)
                .focused($isTextFocused)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: 100, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                )
        }
    }

    // MARK: - Logic

    private func prefillProject() {
        guard let projectId = projectContext.currentProjectId,
              let project = projectContext.project,
              project.id == projectId
        else { return }
        selectedProject = project
    }

    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project = selectedProject,
              let projectId = project.id,
              let accountId = accountContext.currentAccountId,
              !trimmed.isEmpty
        else { return }

        isSaving = true

        do {
            try await projectContext.addNote(
                accountId: accountId,
                projectId: projectId,
                text: trimmed,
                source: "text",
                userId: authManager.currentUser?.uid,
                userName: accountContext.member?.name
            )
            dismiss()
        } catch {
            isSaving = false
            errorMessage = "Failed to save note. Please try again."
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
