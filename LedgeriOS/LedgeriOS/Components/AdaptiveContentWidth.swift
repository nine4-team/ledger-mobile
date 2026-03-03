import SwiftUI

/// Constrains content to a maximum readable width and centers it within available space.
///
/// On iPhone, `maxWidth` (default 720pt) exceeds the screen width so this has no visible effect.
/// On iPad/macOS, content is capped at `maxWidth` and centered horizontally.
struct AdaptiveContentWidth<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = Dimensions.contentMaxWidth, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity) // Centers within available space
    }
}
