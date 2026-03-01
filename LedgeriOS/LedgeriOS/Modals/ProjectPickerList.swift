import SwiftUI
import FirebaseFirestore

/// Single-select project picker that loads all account projects via real-time subscription.
struct ProjectPickerList: View {
    let onSelect: (Project) -> Void

    @Environment(AccountContext.self) private var accountContext

    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var listener: ListenerRegistration?

    var body: some View {
        Group {
            if isLoading {
                LoadingScreen(message: "Loading projects...")
            } else if projects.isEmpty {
                ContentUnavailableView("No projects", systemImage: "folder")
                    .frame(maxHeight: .infinity)
            } else {
                projectList
            }
        }
        .task { await setupListener() }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(projects) { project in
                    Button {
                        onSelect(project)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(project.name.isEmpty ? "(unnamed)" : project.name)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                if !project.clientName.isEmpty {
                                    Text(project.clientName)
                                        .font(Typography.small)
                                        .foregroundStyle(BrandColors.textSecondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                        .padding(.horizontal, Spacing.screenPadding)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.horizontal, Spacing.screenPadding)
                }
            }
        }
    }

    private func setupListener() async {
        guard let accountId = accountContext.currentAccountId else {
            isLoading = false
            return
        }

        listener?.remove()
        let service = ProjectService(syncTracker: NoOpSyncTracker())
        listener = service.subscribeToProjects(accountId: accountId) { newProjects in
            Task { @MainActor in
                self.projects = newProjects.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.isLoading = false
            }
        }
    }
}
