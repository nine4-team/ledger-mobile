import SwiftUI

/// Date picker field styled to match `FormField`.
struct FormDateField: View {
    var label: String = ""
    @Binding var date: Date
    var components: DatePickerComponents = .date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(Typography.label)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            HStack {
                DatePicker("", selection: $date, displayedComponents: components)
                    .labelsHidden()
                Spacer()
            }
            .formInputStyle()
        }
    }
}

#Preview {
    @Previewable @State var date = Date()
    FormDateField(label: "Date", date: $date)
        .padding()
}
