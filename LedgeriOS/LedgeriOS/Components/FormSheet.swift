import SwiftUI

struct FormSheet<Content: View>: View {
    let title: String
    var description: String? = nil
    let primaryAction: FormSheetAction
    var secondaryAction: FormSheetAction? = nil
    var error: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.h2)
                    .foregroundStyle(BrandColors.textPrimary)

                if let description {
                    Text(description)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
                }
            }

            // Content
            ScrollView {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Error
            if let error {
                Text(error)
                    .font(Typography.small)
                    .foregroundStyle(StatusColors.missedText)
            }

            // Actions
            VStack(spacing: Spacing.sm) {
                AppButton(
                    title: primaryAction.title,
                    isLoading: primaryAction.isLoading,
                    isDisabled: primaryAction.isDisabled,
                    action: primaryAction.action
                )

                if let secondaryAction {
                    AppButton(
                        title: secondaryAction.title,
                        variant: .secondary,
                        isLoading: secondaryAction.isLoading,
                        isDisabled: secondaryAction.isDisabled,
                        action: secondaryAction.action
                    )
                }
            }
        }
        .padding(Spacing.screenPadding)
    }
}

#Preview("Basic") {
    FormSheet(
        title: "Edit Item",
        primaryAction: FormSheetAction(title: "Save Changes", action: {})
    ) {
        Text("Form content goes here")
            .font(Typography.body)
    }
}

#Preview("With Error") {
    FormSheet(
        title: "Edit Item",
        description: "Update the item details below.",
        primaryAction: FormSheetAction(title: "Save Changes", action: {}),
        error: "Failed to save. Please try again."
    ) {
        Text("Form content goes here")
            .font(Typography.body)
    }
}

#Preview("Loading") {
    FormSheet(
        title: "Edit Item",
        primaryAction: FormSheetAction(title: "Saving...", isLoading: true, action: {})
    ) {
        Text("Form content goes here")
            .font(Typography.body)
    }
}

#Preview("With Secondary Action") {
    FormSheet(
        title: "Add New Item",
        description: "Fill in the details for the new item.",
        primaryAction: FormSheetAction(title: "Add Item", action: {}),
        secondaryAction: FormSheetAction(title: "Cancel", action: {})
    ) {
        Text("Form content goes here")
            .font(Typography.body)
    }
}
