import SwiftUI

/// Button that opens a sheet/picker, styled to match `FormField`.
/// Use for selections that require a dedicated picker view (e.g. budget category).
struct FormPicker: View {
    var label: String = ""
    var value: String
    var placeholder: String = "—"
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Button(action: action) {
                HStack {
                    Text(value.isEmpty ? placeholder : value)
                        .font(Typography.input)
                        .foregroundStyle(
                            value.isEmpty ? BrandColors.textTertiary : BrandColors.textPrimary
                        )
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .formInputStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    FormPicker(label: "Budget Category", value: "Furniture") { }
        .padding()
}
