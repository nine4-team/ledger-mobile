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
                let isLast = index == options.count - 1
                let prevIsSelected = index > 0 && selection == options[index - 1].id
                let nextIsSelected = !isLast && selection == options[index + 1].id

                Button {
                    selection = option.id
                } label: {
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
                    .foregroundStyle(isSelected ? BrandColors.textPrimary : BrandColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
                    .background(isSelected ? BrandColors.surface : Color.clear)
                    .animation(.easeInOut(duration: 0.2), value: selection)
                }
                .buttonStyle(.plain)

                if !isLast {
                    let showDivider = !isSelected && !nextIsSelected
                    GeometryReader { geo in
                        Rectangle()
                            .fill(showDivider ? BrandColors.borderSecondary : Color.clear)
                            .frame(width: 1, height: geo.size.height * 0.6)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 1)
                    .animation(.easeInOut(duration: 0.2), value: selection)
                }
            }
        }
        .background(BrandColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(BrandColors.border, lineWidth: Dimensions.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
