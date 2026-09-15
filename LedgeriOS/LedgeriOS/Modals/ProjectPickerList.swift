import SwiftUI

/// Single-select project picker backed by the account-level project cache.
#if canImport(FirebaseFirestore)
struct ProjectPickerList: View {
    let onSelect: (Project) -> Void

    @Environment(AccountContext.self) private var accountContext

    private var projects: [Project] {
        accountContext.allProjects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ProjectPickerPresentation(projects: projects, name: { $0.name },
            clientName: { $0.clientName }, onSelect: onSelect)
    }
}
#endif

/// Existing picker presentation with caller-owned, authorized Project choices.
/// Selection has no storage side effects; the owning workflow performs review.
struct ProjectPickerPresentation<ProjectValue: Identifiable>: View {
    let projects: [ProjectValue]
    let name: (ProjectValue) -> String
    let clientName: (ProjectValue) -> String
    let onSelect: (ProjectValue) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Select Project")
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BrandColors.textTertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.screenPadding)
            .padding(.bottom, Spacing.md)

            Group {
                if projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "folder")
                        .frame(maxHeight: .infinity)
                } else {
                    projectList
                }
            }
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
                                Text(name(project).isEmpty ? "(unnamed)" : name(project))
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                if !clientName(project).isEmpty {
                                    Text(clientName(project))
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
}
