import SwiftUI

/// Single-select project picker backed by the account-level project cache.
struct ProjectPickerList: View {
    let onSelect: (Project) -> Void

    @Environment(AccountContext.self) private var accountContext

    @Environment(\.dismiss) private var dismiss

    private var projects: [Project] {
        accountContext.allProjects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

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
}
