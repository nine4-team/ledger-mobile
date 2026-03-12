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
                .presentationDetents([detent(for: style)])
                .presentationDragIndicator(.visible)
        case .selectionMenu, .picker:
            content
                .presentationDetents([detent(for: style)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        case .form:
            content
                .presentationDetents([detent(for: style)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        case .fullSheet:
            content
                .presentationDetents([detent(for: style)])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
    }

    private func detent(for style: SheetStyle) -> PresentationDetent {
        #if os(macOS)
        // macOS sheets don't use the iOS bottom-sheet sizing model;
        // fractional / medium detents produce tiny windows. Use .large
        // for everything except quickMenu which gets a reasonable fraction.
        switch style {
        case .quickMenu:
            return .fraction(0.55)
        case .selectionMenu, .picker:
            return .large
        case .form:
            return .large
        case .fullSheet:
            return .large
        }
        #else
        switch style {
        case .quickMenu:
            return .medium
        case .selectionMenu, .picker:
            return .fraction(0.65)
        case .form:
            return .fraction(0.85)
        case .fullSheet:
            return .large
        }
        #endif
    }
}
