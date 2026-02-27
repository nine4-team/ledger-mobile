import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 36
    var strokeWidth: CGFloat = 3

    private var percentage: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(BrandColors.progressTrack, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(BrandColors.primary, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            Text("\(percentage)%")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(BrandColors.primary)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Half") {
    ProgressRing(progress: 0.5)
}

#Preview("Full") {
    ProgressRing(progress: 1.0)
}

#Preview("Quarter") {
    ProgressRing(progress: 0.25, size: 48, strokeWidth: 4)
}
