import SwiftUI

/// Reusable search field with magnifying glass icon, clear/dismiss button, and theme styling.
///
/// Two styles:
/// - `.form` (default) — solid `inputBackground`, for use in forms and list headers
/// - `.overlay` — translucent `tertiarySystemFill`, for use on glass/material surfaces
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @Binding var isFocused: Bool
    var style: Style = .form
    var onDismiss: (() -> Void)?

    @FocusState private var fieldFocused: Bool

    enum Style {
        /// Solid background for forms and list headers.
        case form
        /// Translucent background for glass/material surfaces.
        case overlay
    }

    init(
        text: Binding<String>,
        placeholder: String = "Search...",
        isFocused: Binding<Bool> = .constant(false),
        style: Style = .form,
        onDismiss: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self._isFocused = isFocused
        self.style = style
        self.onDismiss = onDismiss
    }

    private var isOverlay: Bool { style == .overlay }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(isOverlay ? .system(size: 15) : Typography.body)
                .foregroundStyle(AnyShapeStyle(isOverlay ? AnyShapeStyle(.secondary) : AnyShapeStyle(BrandColors.textSecondary)))

            TextField(placeholder, text: $text)
                .font(isOverlay ? .subheadline : Typography.body)
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
                        .font(isOverlay ? .system(size: 15) : Typography.body)
                        .foregroundStyle(AnyShapeStyle(isOverlay ? AnyShapeStyle(.tertiary) : AnyShapeStyle(BrandColors.textTertiary)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, isOverlay ? Spacing.sm : Spacing.md)
        .padding(.vertical, isOverlay ? 7 : Spacing.sm)
        .background(isOverlay ? Color(.tertiarySystemFill) : BrandColors.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: isOverlay ? 10 : Dimensions.inputRadius))
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
