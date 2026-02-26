import SwiftUI

struct TitledCard<Content: View, HeaderAction: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let headerAction: () -> HeaderAction

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder headerAction: @escaping () -> HeaderAction
    ) {
        self.title = title
        self.content = content
        self.headerAction = headerAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title)
                    .sectionLabelStyle()
                Spacer()
                headerAction()
            }
            Card {
                content()
            }
        }
    }
}

extension TitledCard where HeaderAction == EmptyView {
    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
        self.headerAction = { EmptyView() }
    }
}

#Preview("Basic Titled Card") {
    TitledCard(title: "Project Details") {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Line item one")
            Text("Line item two")
            Text("Line item three")
        }
    }
    .padding()
}

#Preview("Titled Card with Header Action") {
    TitledCard(title: "Items") {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Item A")
            Text("Item B")
        }
    } headerAction: {
        Button("Add New Item") {}
            .font(Typography.label)
            .foregroundStyle(BrandColors.primary)
    }
    .padding()
}
