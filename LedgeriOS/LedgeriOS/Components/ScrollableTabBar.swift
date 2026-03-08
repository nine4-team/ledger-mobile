import SwiftUI

struct TabBarItem: Identifiable {
    let id: String
    let label: String
}

struct ScrollableTabBar: View {
    @Binding var selectedId: String
    let items: [TabBarItem]
    @Namespace private var tabNamespace
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var contentOverflows: Bool {
        contentWidth > containerWidth
    }

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
                            Text(item.label)
                                .font(isSelected ? Typography.buttonSmall : Typography.small)
                                .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textPrimary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(BrandColors.primary.opacity(0.35))
                                            .matchedGeometryEffect(id: "selection", in: tabNamespace)
                                    }
                                }
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(2)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newValue in
                    contentWidth = newValue
                }
            }
            .onChange(of: selectedId) { _, newId in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(newId, anchor: .center)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            containerWidth = newValue
        }
        .overlay(alignment: .trailing) {
            if contentOverflows {
                LinearGradient(
                    colors: [Color(.tertiarySystemFill).opacity(0), Color(.tertiarySystemFill)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 32)
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
        }
        .background(Color(.tertiarySystemFill), in: Capsule())
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
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
