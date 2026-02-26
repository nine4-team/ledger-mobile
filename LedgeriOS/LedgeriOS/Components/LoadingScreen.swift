import SwiftUI

struct LoadingScreen: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()

            if let message {
                Text(message)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("No Message") {
    LoadingScreen()
}

#Preview("With Message") {
    LoadingScreen(message: "Loading your projects...")
}
