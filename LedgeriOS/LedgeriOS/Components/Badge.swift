import SwiftUI

struct Badge: View {
    let text: String
    var color: Color = BrandColors.primary

    var body: some View {
        Text(text)
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.33), lineWidth: 1))
    }
}

#Preview("Default") {
    Badge(text: "In Progress")
}

#Preview("Success") {
    Badge(text: "Completed", color: Color(red: 5/255, green: 150/255, blue: 105/255))
}

#Preview("Error") {
    Badge(text: "Overdue", color: Color(red: 220/255, green: 38/255, blue: 38/255))
}

#Preview("Warning") {
    Badge(text: "At Risk", color: Color(red: 217/255, green: 119/255, blue: 6/255))
}

#Preview("Long Text Truncation") {
    Badge(text: "This is a very long badge label that should truncate")
        .frame(maxWidth: 150)
}
