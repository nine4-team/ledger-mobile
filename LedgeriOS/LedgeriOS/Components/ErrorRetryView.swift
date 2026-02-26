import SwiftUI

struct ErrorRetryView: View {
    var message: String = "Something went wrong"
    var onRetry: (() -> Void)? = nil
    var isOffline: Bool = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(BrandColors.textSecondary)

            Text(message)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .multilineTextAlignment(.center)

            if isOffline {
                Text("You appear to be offline")
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            if let onRetry {
                AppButton(title: "Try Again", variant: .secondary, action: onRetry)
            }
        }
        .padding(Spacing.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Basic Error") {
    ErrorRetryView()
}

#Preview("With Retry") {
    ErrorRetryView(
        message: "Failed to load projects",
        onRetry: {}
    )
}

#Preview("Offline") {
    ErrorRetryView(
        message: "Unable to connect to server",
        onRetry: {},
        isOffline: true
    )
}
