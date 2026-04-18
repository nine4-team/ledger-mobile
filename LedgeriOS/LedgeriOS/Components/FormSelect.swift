import SwiftUI

/// Menu-based dropdown field styled to match `FormField`.
/// Use for inline option selection (status, type, etc.).
struct FormSelect: View {
    var label: String = ""
    @Binding var selection: String
    var options: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Menu {
                ForEach(options, id: \.0) { value, display in
                    Button(display) { selection = value }
                }
            } label: {
                HStack {
                    Text(options.first { $0.0 == selection }?.1 ?? "—")
                        .font(Typography.input)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .formInputStyle()
                .contentShape(Rectangle())
            }
        }
    }
}

#Preview {
    @Previewable @State var status = "pending"
    FormSelect(label: "Status", selection: $status, options: [
        ("pending", "Pending"),
        ("complete", "Complete"),
        ("cancelled", "Cancelled"),
    ])
    .padding()
}
