import SwiftUI

struct TabBarItem: Identifiable {
    let id: String
    let label: String
}

struct ScrollableTabBar: View {
    @Binding var selectedId: String
    let items: [TabBarItem]
    var showsBottomBorder = true

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        let isSelected = item.id == selectedId
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedId = item.id
                            }
                        } label: {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Text(item.label)
                                    .font(isSelected ? Typography.button : Typography.small)
                                    .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
                                    .padding(.horizontal, Spacing.md)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(isSelected ? BrandColors.primary : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(height: 36)
                            .contentShape(Rectangle())
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .onChange(of: selectedId) { _, newId in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(newId, anchor: .center)
                }
            }
        }
        .frame(height: 36)
        .overlay(alignment: .bottom) {
            if showsBottomBorder {
                Rectangle()
                    .fill(BrandColors.borderSecondary)
                    .frame(height: Dimensions.borderWidth)
            }
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
