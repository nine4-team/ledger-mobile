import SwiftUI

struct MultiStepFormSheet<Content: View>: View {
    let title: String
    var description: String? = nil
    let currentStep: Int
    let totalSteps: Int
    let primaryAction: FormSheetAction
    var secondaryAction: FormSheetAction? = nil
    var error: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        FormSheet(
            title: title,
            description: description,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            error: error
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Step \(currentStep) of \(totalSteps)")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)

                content
            }
        }
    }
}

#Preview("Step 1 of 3") {
    MultiStepFormSheet(
        title: "Create Project",
        currentStep: 1,
        totalSteps: 3,
        primaryAction: FormSheetAction(title: "Next", action: {}),
        secondaryAction: FormSheetAction(title: "Cancel", action: {})
    ) {
        Text("Step 1 content goes here")
            .font(Typography.body)
    }
}

#Preview("Step 2 of 3") {
    MultiStepFormSheet(
        title: "Create Project",
        description: "Add budget details",
        currentStep: 2,
        totalSteps: 3,
        primaryAction: FormSheetAction(title: "Next", action: {}),
        secondaryAction: FormSheetAction(title: "Back", action: {})
    ) {
        Text("Step 2 content goes here")
            .font(Typography.body)
    }
}
