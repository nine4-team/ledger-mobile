import SwiftUI

/// Simple control bar with an inline search field and optional add button inside a glass capsule.
///
/// Use this for list screens that only need search + add (e.g. Spaces).
/// For screens that also need sort/filter/select-all, use `NativeListControlBar`.
struct SearchControlBar: View {
    @Binding var searchText: String
    var searchPlaceholder: String = "Search..."
    @Binding var isFocused: Bool
    var onAdd: (() -> Void)?

    init(
        searchText: Binding<String>,
        searchPlaceholder: String = "Search...",
        isFocused: Binding<Bool> = .constant(false),
        onAdd: (() -> Void)? = nil
    ) {
        self._searchText = searchText
        self.searchPlaceholder = searchPlaceholder
        self._isFocused = isFocused
        self.onAdd = onAdd
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            SearchField(
                text: $searchText,
                placeholder: searchPlaceholder,
                isFocused: $isFocused,
                style: .overlay
            )

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(CircleBarButtonStyle())
                .tint(.secondary)
                .font(.system(size: 16))
                .imageScale(.medium)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .overlay(Circle().stroke(BrandColors.border, lineWidth: Dimensions.borderWidth))
                .accessibilityLabel("Add")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .modifier(CardGlassModifier())
        .frame(maxWidth: Dimensions.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Previews

#Preview("Search + Add") {
    SearchControlBar(
        searchText: .constant(""),
        searchPlaceholder: "Search spaces...",
        onAdd: {}
    )
}

#Preview("Search Only") {
    SearchControlBar(
        searchText: .constant(""),
        searchPlaceholder: "Search..."
    )
}

#Preview("With Text") {
    SearchControlBar(
        searchText: .constant("Living Room"),
        searchPlaceholder: "Search spaces...",
        onAdd: {}
    )
}
