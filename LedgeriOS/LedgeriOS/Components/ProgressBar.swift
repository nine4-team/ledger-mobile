import SwiftUI

struct ProgressBar: View {
    let percentage: Double
    let fillColor: Color
    var trackColor: Color = BrandColors.progressTrack
    var height: CGFloat = 6
    var overflowPercentage: Double? = nil
    var overflowColor: Color? = nil

    private var clampedPercentage: Double {
        ProgressBarCalculations.clampPercentage(percentage)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(width: geometry.size.width, height: height)

                Capsule()
                    .fill(fillColor)
                    .frame(width: clampedPercentage / 100 * geometry.size.width, height: height)

                if let overflowPercentage, let overflowColor, overflowPercentage > 0 {
                    Capsule()
                        .fill(overflowColor)
                        .frame(width: overflowPercentage / 100 * geometry.size.width, height: height)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityValue("\(Int(percentage))%")
    }
}

#Preview("50% filled") {
    ProgressBar(percentage: 50, fillColor: BrandColors.primary)
        .padding()
}

#Preview("100% filled") {
    ProgressBar(percentage: 100, fillColor: BrandColors.primary)
        .padding()
}

#Preview("Over budget with overflow") {
    ProgressBar(
        percentage: 100,
        fillColor: BrandColors.primary,
        overflowPercentage: 30,
        overflowColor: StatusColors.overflowBar
    )
    .padding()
}

#Preview("Empty (0%)") {
    ProgressBar(percentage: 0, fillColor: BrandColors.primary)
        .padding()
}
