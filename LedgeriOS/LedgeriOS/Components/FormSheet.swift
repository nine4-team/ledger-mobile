import SwiftUI

struct FormSheet<Content: View>: View {
    let title: String
    var description: String? = nil
    let primaryAction: FormSheetAction
    var secondaryAction: FormSheetAction? = nil
    var error: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Description (optional subtitle below nav bar title)
                if let description {
                    Text(description)
                        .font(Typography.small)
                        .foregroundStyle(BrandColors.textSecondary)
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
                if let secondaryAction {
                    HStack(spacing: Spacing.sm) {
                        AppButton(
                            title: secondaryAction.title,
                            variant: .secondary,
                            isLoading: secondaryAction.isLoading,
                            isDisabled: secondaryAction.isDisabled,
                            action: secondaryAction.action
                        )
                        AppButton(
                            title: primaryAction.title,
                            isLoading: primaryAction.isLoading,
                            isDisabled: primaryAction.isDisabled,
                            action: primaryAction.action
                        )
                    }
                } else {
                    AppButton(
                        title: primaryAction.title,
                        isLoading: primaryAction.isLoading,
                        isDisabled: primaryAction.isDisabled,
                        action: primaryAction.action
                    )
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.screenPadding)
            .frame(maxWidth: Dimensions.formMaxWidth)
            .frame(maxWidth: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
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
