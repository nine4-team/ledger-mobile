import SwiftUI

struct FormSheet<Content: View>: View {
    let title: String
    var description: String? = nil
    var showDismissButton: Bool = true
    let primaryAction: FormSheetAction
    var secondaryAction: FormSheetAction? = nil
    var error: String? = nil
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if showDismissButton {
            formContent
        } else {
            NavigationStack {
                formContent
                    .navigationTitle(title)
                    .navBarTitleDisplayMode(.inline)
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header with dismiss button (only when not using nav bar)
            if showDismissButton {
                HStack {
                    Text(title)
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
            }

            // Description (optional subtitle below title)
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
        .background(BrandColors.surface)
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
