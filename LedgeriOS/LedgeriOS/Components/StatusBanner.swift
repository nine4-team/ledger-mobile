import SwiftUI

struct StatusBanner<Actions: View>: View {
    let message: String
    var variant: StatusBannerVariant = .error
    var autoDismissAfter: TimeInterval? = nil
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    init(
        message: String,
        variant: StatusBannerVariant = .error,
        autoDismissAfter: TimeInterval? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.message = message
        self.variant = variant
        self.autoDismissAfter = autoDismissAfter
        self.onDismiss = onDismiss
        self.actions = actions()
    }

    private var icon: String {
        switch variant {
        case .error, .warning:
            "exclamationmark.triangle"
        case .info:
            "info.circle"
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .error:
            StatusColors.missedBackground
        case .warning:
            StatusColors.inProgressBackground
        case .info:
            BrandColors.surface
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .error:
            StatusColors.missedText
        case .warning:
            StatusColors.inProgressText
        case .info:
            BrandColors.textPrimary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(foregroundColor)

                Text(message)
                    .font(Typography.small)
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(foregroundColor)
                    }
                }
            }

            actions
        }
        .padding(Spacing.cardPadding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Dimensions.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
        .task(id: autoDismissAfter) {
            if let duration = autoDismissAfter {
                try? await Task.sleep(for: .seconds(duration))
                onDismiss?()
            }
        }
    }
}

#Preview("Error") {
    StatusBanner(
        message: "Failed to save changes. Please try again.",
        onDismiss: {}
    )
    .padding()
}

#Preview("Warning") {
    StatusBanner(
        message: "You have unsaved changes.",
        variant: .warning,
        onDismiss: {}
    )
    .padding()
}

#Preview("Info") {
    StatusBanner(
        message: "Your data was last synced 5 minutes ago.",
        variant: .info
    )
    .padding()
}

#Preview("With Actions") {
    StatusBanner(
        message: "Connection lost. Some features may be unavailable.",
        variant: .warning,
        onDismiss: {}
    ) {
        Button("Retry") {}
            .font(Typography.buttonSmall)
    }
    .padding()
}
