import SwiftUI

struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var badge: String? = nil
    var onEdit: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: isExpanded)

                    Text(title)
                        .sectionLabelStyle()

                    if let badge {
                        Text(badge)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Spacer()

                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if let onAdd {
                        Button {
                            onAdd()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(BrandColors.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
    }
}

#Preview("Expanded") {
    @Previewable @State var isExpanded = true

    CollapsibleSection(title: "Line Items", isExpanded: $isExpanded, badge: "3") {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Item One")
            Text("Item Two")
            Text("Item Three")
        }
        .padding(.top, Spacing.xs)
    }
    .padding()
}

#Preview("Collapsed") {
    @Previewable @State var isExpanded = false

    CollapsibleSection(title: "Line Items", isExpanded: $isExpanded, badge: "3") {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Item One")
            Text("Item Two")
            Text("Item Three")
        }
        .padding(.top, Spacing.xs)
    }
    .padding()
}

#Preview("With Actions") {
    @Previewable @State var isExpanded = true

    CollapsibleSection(
        title: "Materials",
        isExpanded: $isExpanded,
        badge: "5",
        onEdit: { print("Edit tapped") },
        onAdd: { print("Add tapped") }
    ) {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Lumber")
            Text("Concrete")
            Text("Steel")
        }
        .padding(.top, Spacing.xs)
    }
    .padding()
}
