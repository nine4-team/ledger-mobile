import SwiftUI

struct ProjectCard: View {
    let project: Project
    let budgetPreview: [BudgetProgress.CategoryProgress]

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(project.name.isEmpty ? "Project" : project.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text(project.clientName.isEmpty ? "No client" : project.clientName)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)

                    ForEach(budgetPreview) { cat in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(cat.name)
                                .font(Typography.small)
                                .foregroundStyle(BrandColors.textSecondary)
                            BudgetProgressView(
                                spentCents: cat.spentCents,
                                budgetCents: cat.budgetCents,
                                compact: true
                            )
                        }
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = project.mainImageUrl, !url.isEmpty {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 140).clipped()
                default:
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(BrandColors.surfaceTertiary)
            .frame(height: 100)
            .overlay {
                Text("No image")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textTertiary)
            }
    }
}

#Preview("With Budget Preview") {
    var project = Project()
    project.name = "Bradshaws Desert Color Rental"
    project.clientName = "CharReese, Delynn & Bryce Bradshaw"

    let categories = [
        BudgetProgress.CategoryProgress(
            id: "1", name: "Furnishings",
            budgetCents: 10_320_000, spentCents: 10_093_600,
            categoryType: .general, excludeFromOverallBudget: false
        ),
    ]

    return ProjectCard(project: project, budgetPreview: categories)
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}

#Preview("No Budget") {
    var project = Project()
    project.name = "Empty Project"
    project.clientName = "No client"

    return ProjectCard(project: project, budgetPreview: [])
        .padding(Spacing.screenPadding)
        .preferredColorScheme(.dark)
}
