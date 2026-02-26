import SwiftUI

struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var errorText: String? = nil
    var helperText: String? = nil
    var isDisabled: Bool = false
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(BrandColors.textSecondary)

            TextField(placeholder, text: $text, axis: axis)
                .font(Typography.input)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background(BrandColors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: Dimensions.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Dimensions.inputRadius)
                        .stroke(
                            errorText != nil ? BrandColors.destructive : BrandColors.border,
                            lineWidth: Dimensions.borderWidth
                        )
                )

            if let error = errorText {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.destructive)
            } else if let helper = helperText {
                Text(helper)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
        .disabled(isDisabled)
    }
}

#Preview("Normal") {
    @Previewable @State var text = ""
    FormField(label: "Project Name", text: $text, placeholder: "Enter project name")
        .padding()
}

#Preview("Error") {
    @Previewable @State var text = "Bad input"
    FormField(
        label: "Budget",
        text: $text,
        placeholder: "Enter amount",
        errorText: "Must be a positive number"
    )
    .padding()
}

#Preview("Helper") {
    @Previewable @State var text = ""
    FormField(
        label: "Description",
        text: $text,
        placeholder: "Optional",
        helperText: "Briefly describe the project scope"
    )
    .padding()
}

#Preview("Disabled") {
    @Previewable @State var text = "Locked value"
    FormField(
        label: "Reference ID",
        text: $text,
        placeholder: "",
        isDisabled: true
    )
    .padding()
}
