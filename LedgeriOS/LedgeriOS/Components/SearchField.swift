import SwiftUI

/// Reusable search field with magnifying glass icon, clear/dismiss button, and theme styling.
/// Uses `BrandColors.surface` background with border and shadow to match control bar buttons.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @Binding var isFocused: Bool
    var onDismiss: (() -> Void)?

    @FocusState private var fieldFocused: Bool

    init(
        text: Binding<String>,
        placeholder: String = "Search...",
        isFocused: Binding<Bool> = .constant(false),
        onDismiss: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self._isFocused = isFocused
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)

            TextField(placeholder, text: $text)
                .font(Typography.body)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .platformTextInputAutocapitalization(.never)

            if !text.isEmpty || onDismiss != nil {
                Button {
                    if text.isEmpty {
                        onDismiss?()
                    } else {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 44)
        .background(BrandColors.surface)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .onChange(of: isFocused) { _, newValue in
            fieldFocused = newValue
        }
        .onChange(of: fieldFocused) { _, newValue in
            isFocused = newValue
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    SearchField(text: .constant(""), placeholder: "Search items...")
        .padding()
}

#Preview("With Text") {
    SearchField(text: .constant("Pillow"), placeholder: "Search items...")
        .padding()
}

#Preview("With Dismiss") {
    SearchField(text: .constant(""), placeholder: "Search...", onDismiss: {})
        .padding()
}
