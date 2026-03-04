import SwiftUI

struct ListStateControls: View {
    @Binding var searchText: String
    var isSearchVisible: Bool
    var placeholder: String = "Search..."

    var body: some View {
        if isSearchVisible {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BrandColors.textSecondary)

                TextField(placeholder, text: $searchText)
                    .font(Typography.input)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(BrandColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("Visible Empty") {
    VStack {
        ListStateControls(searchText: .constant(""), isSearchVisible: true)
            .padding()
        Spacer()
    }
}

#Preview("Visible with Text") {
    VStack {
        ListStateControls(searchText: .constant("Pillow"), isSearchVisible: true)
            .padding()
        Spacer()
    }
}

#Preview("Hidden") {
    VStack {
        ListStateControls(searchText: .constant(""), isSearchVisible: false)
            .padding()
        Spacer()
    }
}
