import SwiftUI

/// Highlights a card when it is the current find match.
/// Reads `findEntityID` from environment (set by `.findEntity(id:)`).
struct FindMatchHighlight: ViewModifier {
    @Environment(FindStateManager.self) private var findState
    @Environment(\.findEntityID) private var entityID

    private var isCurrent: Bool {
        guard let entityID, findState.isActive else { return false }
        return findState.currentMatchID == entityID
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Dimensions.cardRadius)
                    .stroke(BrandColors.primary, lineWidth: 2.5)
                    .opacity(isCurrent ? 1 : 0)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    /// Adds a card-level highlight border when this card is the current find match.
    /// Requires `.findEntity(id:)` to be set on this view or an ancestor.
    func findMatchHighlight() -> some View {
        modifier(FindMatchHighlight())
    }
}
