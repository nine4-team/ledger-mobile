import SwiftUI

/// Toggle row styled to match `FormField` — label left, toggle right, bordered container.
struct FormToggle: View {
    var label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.input)
                .foregroundStyle(BrandColors.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(BrandColors.primary)
        }
        .formInputStyle()
    }
}

#Preview {
    @Previewable @State var isOn = false
    FormToggle(label: "Email Receipt", isOn: $isOn)
        .padding()
}
