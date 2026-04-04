import SwiftUI

struct SegmentOption<T: Hashable> {
    let id: T
    let label: String
    let icon: Image?

    init(id: T, label: String, icon: Image? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
    }
}

struct SegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [SegmentOption<T>]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isSelected = selection == option.id

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = option.id
                    }
                } label: {
                    VStack(spacing: 0) {
                        Spacer()
                        Group {
                            if let icon = option.icon {
                                HStack(spacing: 4) {
                                    icon
                                    Text(option.label)
                                }
                            } else {
                                Text(option.label)
                            }
                        }
                        .font(isSelected ? Typography.button : Typography.small)
                        .foregroundStyle(isSelected ? BrandColors.primary : BrandColors.textSecondary)
                        Spacer()
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isSelected ? BrandColors.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
        .background(BrandColors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BrandColors.borderSecondary)
                .frame(height: Dimensions.borderWidth)
        }
    }
}

#Preview("2 Segments") {
    @Previewable @State var selection = "active"

    let options = [
        SegmentOption(id: "active", label: "Active"),
        SegmentOption(id: "archived", label: "Archived"),
    ]

    SegmentedControl(selection: $selection, options: options)
        .padding()
}

#Preview("3 Segments") {
    @Previewable @State var selection = "all"

    let options = [
        SegmentOption(id: "all", label: "All", icon: Image(systemName: "list.bullet")),
        SegmentOption(id: "open", label: "Open", icon: Image(systemName: "circle")),
        SegmentOption(id: "closed", label: "Closed", icon: Image(systemName: "checkmark.circle")),
    ]

    SegmentedControl(selection: $selection, options: options)
        .padding()
}
