import SwiftUI

struct TabBarItem: Identifiable {
    let id: String
    let label: String
}

struct ScrollableTabBar: View {
    @Binding var selectedId: String
    let items: [TabBarItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(items) { item in
                    let isSelected = item.id == selectedId
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedId = item.id
                        }
                    } label: {
                        Text(item.label)
                            .font(isSelected ? Typography.button : Typography.body)
                            .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(BrandColors.primary.opacity(0.15))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sm)
        }
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColors.borderSecondary)
                .frame(height: Dimensions.borderWidth)
        }
    }
}

#Preview("Two Tabs") {
    struct PreviewWrapper: View {
        @State private var selected = "active"
        var body: some View {
            ScrollableTabBar(
                selectedId: $selected,
                items: [
                    TabBarItem(id: "active", label: "Active"),
                    TabBarItem(id: "archived", label: "Archived"),
                ]
            )
        }
    }
    return PreviewWrapper()
        .preferredColorScheme(.dark)
}

#Preview("Five Tabs") {
    struct PreviewWrapper: View {
        @State private var selected = "budget"
        var body: some View {
            ScrollableTabBar(
                selectedId: $selected,
                items: [
                    TabBarItem(id: "budget", label: "Budget"),
                    TabBarItem(id: "items", label: "Items"),
                    TabBarItem(id: "transactions", label: "Transactions"),
                    TabBarItem(id: "spaces", label: "Spaces"),
                    TabBarItem(id: "accounting", label: "Accounting"),
                ]
            )
        }
    }
    return PreviewWrapper()
        .preferredColorScheme(.dark)
}
