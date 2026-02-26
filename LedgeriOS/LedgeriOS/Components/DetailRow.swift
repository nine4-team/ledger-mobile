import SwiftUI

struct DetailRow<Value: View>: View {
    let label: String
    let showDivider: Bool
    let onTap: (() -> Void)?
    @ViewBuilder let value: () -> Value

    init(
        label: String,
        showDivider: Bool = true,
        onTap: (() -> Void)? = nil,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.label = label
        self.showDivider = showDivider
        self.onTap = onTap
        self.value = value
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                rowContent
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(Typography.small)
                    .foregroundStyle(BrandColors.textSecondary)

                Spacer()

                value()

                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .padding(.vertical, Spacing.sm)

            if showDivider {
                Rectangle()
                    .fill(BrandColors.borderSecondary)
                    .frame(height: Dimensions.borderWidth)
            }
        }
    }
}

extension DetailRow where Value == Text {
    init(
        label: String,
        value: String,
        showDivider: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.init(label: label, showDivider: showDivider, onTap: onTap) {
            Text(value)
                .font(Typography.body)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }
}

#Preview("Text Value") {
    VStack(spacing: 0) {
        DetailRow(label: "Status", value: "Active")
        DetailRow(label: "Category", value: "Equipment")
        DetailRow(label: "Last Updated", value: "Feb 25, 2026", showDivider: false)
    }
    .padding(.horizontal)
}

#Preview("Custom Value") {
    VStack(spacing: 0) {
        DetailRow(label: "Budget") {
            HStack(spacing: 4) {
                Text("$1,200")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        DetailRow(label: "Tags", showDivider: false) {
            HStack(spacing: 4) {
                Text("Rental")
                Text("Audio")
            }
            .font(Typography.small)
            .foregroundStyle(BrandColors.textSecondary)
        }
    }
    .padding(.horizontal)
}

#Preview("Tappable") {
    VStack(spacing: 0) {
        DetailRow(label: "Project", value: "Spring Campaign", onTap: {})
        DetailRow(label: "Assigned To", value: "Ben M.", onTap: {})
        DetailRow(label: "Notes", value: "See attached brief", showDivider: false, onTap: {})
    }
    .padding(.horizontal)
}

#Preview("No Divider") {
    VStack(spacing: 0) {
        DetailRow(label: "Serial Number", value: "SN-00421", showDivider: false)
    }
    .padding(.horizontal)
}
