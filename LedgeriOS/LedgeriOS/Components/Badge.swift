import SwiftUI

struct Badge: View {
    let text: String
    var color: Color = BrandColors.primary
    var backgroundOpacity: Double = 0.10
    var borderOpacity: Double = 0.20

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(backgroundOpacity))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(borderOpacity), lineWidth: 1))
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
