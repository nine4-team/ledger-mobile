import SwiftUI

enum AppButtonVariant {
    case primary
    case secondary
}

struct AppButton: View {
    let title: String
    var variant: AppButtonVariant = .primary
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var leftIcon: Image? = nil
    let action: () -> Void

    private var isInactive: Bool {
        isDisabled || isLoading
    }

    private var backgroundColor: Color {
        if isInactive {
            return BrandColors.buttonDisabledBackground
        }
        switch variant {
        case .primary:
            return BrandColors.primary
        case .secondary:
            return BrandColors.buttonSecondaryBackground
        }
    }

    private var foregroundColor: Color {
        if isInactive {
            return BrandColors.textDisabled
        }
        switch variant {
        case .primary:
            return .white
        case .secondary:
            return BrandColors.textPrimary
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                } else {
                    HStack(spacing: Spacing.xs) {
                        if let icon = leftIcon {
                            icon
                                .renderingMode(.template)
                        }
                        Text(title)
                    }
                }
            }
            .font(Typography.button)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.buttonRadius))
            .overlay {
                if variant == .secondary && !isInactive {
                    RoundedRectangle(cornerRadius: Dimensions.buttonRadius)
                        .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
                }
            }
        }
        .buttonStyle(AppButtonStyle())
        .disabled(isInactive)
    }
}

private struct AppButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("Primary") {
    VStack(spacing: Spacing.md) {
        AppButton(title: "Save to Draft") {}
        AppButton(title: "Add New Item", leftIcon: Image(systemName: "plus")) {}
    }
    .padding()
}

#Preview("Secondary") {
    VStack(spacing: Spacing.md) {
        AppButton(title: "Cancel", variant: .secondary) {}
        AppButton(title: "View Details", variant: .secondary, leftIcon: Image(systemName: "eye")) {}
    }
    .padding()
}

#Preview("Loading") {
    VStack(spacing: Spacing.md) {
        AppButton(title: "Save to Draft", isLoading: true) {}
        AppButton(title: "Cancel", variant: .secondary, isLoading: true) {}
    }
    .padding()
}

#Preview("Disabled") {
    VStack(spacing: Spacing.md) {
        AppButton(title: "Save to Draft", isDisabled: true) {}
        AppButton(title: "Cancel", variant: .secondary, isDisabled: true) {}
    }
    .padding()
}
