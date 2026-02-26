import SwiftUI

enum SelectorIndicator {
    case dot
    case check
}

struct SelectorCircle: View {
    let isSelected: Bool
    var indicator: SelectorIndicator = .dot
    var size: CGFloat = 18

    static func dotSize(for circleSize: CGFloat) -> CGFloat {
        circleSize * 0.56
    }

    static func checkmarkSize(for circleSize: CGFloat) -> CGFloat {
        circleSize * 0.6
    }

    var body: some View {
        ZStack {
            if isSelected && indicator == .check {
                Circle()
                    .fill(BrandColors.primary)
                    .frame(width: size, height: size)
                Image(systemName: "checkmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.checkmarkSize(for: size), height: Self.checkmarkSize(for: size))
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            } else {
                Circle()
                    .strokeBorder(BrandColors.border, lineWidth: Dimensions.borderWidth)
                    .frame(width: size, height: size)
                if isSelected && indicator == .dot {
                    Circle()
                        .fill(BrandColors.primary)
                        .frame(
                            width: Self.dotSize(for: size),
                            height: Self.dotSize(for: size)
                        )
                }
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

#Preview("Unselected") {
    SelectorCircle(isSelected: false)
}

#Preview("Selected Dot") {
    SelectorCircle(isSelected: true, indicator: .dot)
}

#Preview("Selected Check") {
    SelectorCircle(isSelected: true, indicator: .check)
}

#Preview("All States") {
    HStack(spacing: 24) {
        VStack(spacing: 12) {
            Text("Unselected").font(.caption)
            SelectorCircle(isSelected: false, indicator: .dot)
            SelectorCircle(isSelected: false, indicator: .check)
        }
        VStack(spacing: 12) {
            Text("Selected Dot").font(.caption)
            SelectorCircle(isSelected: true, indicator: .dot)
        }
        VStack(spacing: 12) {
            Text("Selected Check").font(.caption)
            SelectorCircle(isSelected: true, indicator: .check)
        }
        VStack(spacing: 12) {
            Text("Large (28pt)").font(.caption)
            SelectorCircle(isSelected: true, indicator: .dot, size: 28)
            SelectorCircle(isSelected: true, indicator: .check, size: 28)
        }
    }
    .padding()
}
