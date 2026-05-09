import SwiftUI

struct DetailRow<Value: View>: View {
    let label: String
    let showDivider: Bool
    let onTap: (() -> Void)?
    let copyValue: String?
    @ViewBuilder let value: () -> Value
    @State private var didCopy = false

    init(
        label: String,
        showDivider: Bool = true,
        onTap: (() -> Void)? = nil,
        copyValue: String? = nil,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.label = label
        self.showDivider = showDivider
        self.onTap = onTap
        self.copyValue = copyValue
        self.value = value
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                rowContent
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            copyableRowContent
        }
    }

    private var copyableRowContent: some View {
        rowContent
            .textSelection(.enabled)
            .contextMenu {
                if let copyValue, !copyValue.isEmpty {
                    Button {
                        copy(copyValue)
                    } label: {
                        Label("Copy \(label)", systemImage: "doc.on.doc")
                    }
                }
            }
            .accessibilityHint(copyValue == nil ? "" : "Long press for copy options.")
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
            .overlay(alignment: .trailing) {
                if didCopy {
                    copiedBadge
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: didCopy)

            if showDivider {
                Rectangle()
                    .fill(BrandColors.borderSecondary)
                    .frame(height: Dimensions.borderWidth)
            }
        }
    }

    private var copiedBadge: some View {
        Label("Copied \(label)", systemImage: "checkmark")
            .font(Typography.caption.weight(.semibold))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(BrandColors.surface, in: Capsule())
            .overlay(Capsule().stroke(BrandColors.border, lineWidth: Dimensions.borderWidth))
            .foregroundStyle(BrandColors.primary)
    }

    private func copy(_ string: String) {
        Clipboard.copy(string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                didCopy = false
            }
        }
    }
}

extension DetailRow {
    init(
        label: String,
        value: String,
        showDivider: Bool = true,
        onTap: (() -> Void)? = nil
    ) where Value == AnyView {
        self.init(
            label: label,
            showDivider: showDivider,
            onTap: onTap,
            copyValue: onTap == nil ? value : nil
        ) {
            AnyView(
                FindableText(value)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textPrimary)
            )
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
