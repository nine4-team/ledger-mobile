import SwiftUI

/// Standardized sheet presentation sizes.
/// Single fixed height per style — no resizing, no multi-snap-point friction.
/// Content scrolls inside the sheet. Tap background to dismiss.
enum SheetStyle {
    /// Small menu, ≤6 items, single-select, dismiss on tap.
    case quickMenu

    /// Multi-select or scrollable list (filters, large action menus).
    case selectionMenu

    /// Input fields, creation/edit flows.
    case form

    /// Single-select from variable-length list.
    case picker

    /// Full-height sheet for complex content (item browsers with search/filter).
    case fullSheet
}

extension View {
    /// Apply a standardized sheet presentation style.
    func sheetStyle(_ style: SheetStyle) -> some View {
        modifier(SheetStyleModifier(style: style))
    }
}

private struct SheetStyleModifier: ViewModifier {
    let style: SheetStyle

    func body(content: Content) -> some View {
        switch style {
        case .quickMenu:
            content
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .selectionMenu, .picker:
            content
                .presentationDetents([.fraction(0.65)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        case .form:
            content
                .presentationDetents([.fraction(0.85)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        case .fullSheet:
            content
                .presentationDetents([.large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
    }
}
