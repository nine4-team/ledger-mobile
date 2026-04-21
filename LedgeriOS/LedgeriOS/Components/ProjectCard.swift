import SwiftUI

struct ProjectCard: View {
    let project: Project
    let budgetPreview: [BudgetProgress.CategoryProgress]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var hasHeroImage: Bool {
        if let url = project.mainImageUrl, !url.isEmpty { return true }
        return false
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if horizontalSizeClass != .compact || hasHeroImage {
                    heroImage
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    FindableText(project.name.isEmpty ? "Project" : project.name)
                        .font(Typography.h3)
                        .foregroundStyle(BrandColors.textPrimary)

                    FindableText(project.clientName.isEmpty ? "No client" : project.clientName)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)

                    if !budgetPreview.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            ForEach(budgetPreview) { cat in
                                BudgetProgressPreview(
                                    categoryName: cat.name,
                                    spentCents: cat.spentCents,
                                    budgetCents: cat.budgetCents,
                                    isFeeCategory: cat.isFeeCategory
                                )
                            }
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
                .padding(Spacing.cardPadding)
            }
        }
        .findEntity(id: project.id)
        .findMatchHighlight()
    }

    @ViewBuilder
    private var heroImage: some View {
        if let url = project.mainImageUrl, !url.isEmpty {
            FirebaseImage(url: url, thumbnailUrl: project.mainImageThumbUrlMd, contentMode: .fill) {
                imagePlaceholder
            }
            .frame(height: 140).clipped()
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(BrandColors.surfaceTertiary)
            .frame(height: 100)
            .overlay {
                Image(systemName: "photo")
                    .font(Typography.h1)
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
        BudgetProgress.CategoryProgress(
            id: "2", name: "Additional Requests",
            budgetCents: 5_000_000, spentCents: 5_356_000,
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
