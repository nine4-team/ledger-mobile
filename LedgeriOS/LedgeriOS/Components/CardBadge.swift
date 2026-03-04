import SwiftUI

/// Shared badge data type for card headers.
/// Used by TransactionCardCalculations and ItemCardCalculations.
struct CardBadge: Equatable {
    let text: String
    let color: Color
    var backgroundOpacity: Double = 0.10
    var borderOpacity: Double = 0.20
}
