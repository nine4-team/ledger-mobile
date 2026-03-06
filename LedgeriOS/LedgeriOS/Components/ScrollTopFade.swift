import SwiftUI

/// Adds a gradient overlay at the top of the content, creating a shadow effect
/// where cards fade as they scroll upward beneath a tab bar.
/// Adapts opacity for light and dark mode automatically.
///
/// Apply this to the content view **below** a `ScrollableTabBar` in a VStack.
struct ScrollContentTopFadeModifier: ViewModifier {
    var height: CGFloat = 42

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [BrandColors.background, BrandColors.background.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func scrollContentTopFade(height: CGFloat = 42) -> some View {
        modifier(ScrollContentTopFadeModifier(height: height))
    }
}
