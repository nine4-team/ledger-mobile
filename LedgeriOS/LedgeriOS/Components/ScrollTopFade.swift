import SwiftUI

/// Adds a dark gradient overlay at the top of the content, creating a shadow effect
/// where cards fade into darkness as they scroll upward beneath a tab bar.
///
/// Apply this to the content view **below** a `ScrollableTabBar` in a VStack.
struct ScrollContentTopFadeModifier: ViewModifier {
    var height: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
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
    func scrollContentTopFade(height: CGFloat = 40) -> some View {
        modifier(ScrollContentTopFadeModifier(height: height))
    }
}
