import SwiftUI

struct ScrollTopFadeModifier: ViewModifier {
    var height: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [BrandColors.background, BrandColors.background.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func scrollTopFade(height: CGFloat = 24) -> some View {
        modifier(ScrollTopFadeModifier(height: height))
    }
}
