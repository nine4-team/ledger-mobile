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

    /// On macOS, menus should use popover; forms/full sheets stay as sheets.
    var usesPopoverOnMac: Bool {
        switch self {
        case .quickMenu, .selectionMenu, .picker: return true
        case .form, .fullSheet: return false
        }
    }
}

// MARK: - Adaptive Presentation

extension View {
    /// Platform-adaptive presentation: popover on macOS for menus, sheet on iOS.
    /// Replaces `.sheet { content.sheetStyle(.x) }` pattern.
    func adaptivePresentation<C: View>(
        isPresented: Binding<Bool>,
        style: SheetStyle,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        modifier(AdaptivePresentationModifier(
            isPresented: isPresented,
            style: style,
            onDismiss: onDismiss,
            sheetContent: content
        ))
    }

    /// Item-binding variant of adaptive presentation.
    func adaptivePresentation<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        style: SheetStyle,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        modifier(AdaptivePresentationItemModifier(
            item: item,
            style: style,
            onDismiss: onDismiss,
            sheetContent: content
        ))
    }
}

// MARK: - Bool-binding modifier

private struct AdaptivePresentationModifier<C: View>: ViewModifier {
    @Binding var isPresented: Bool
    let style: SheetStyle
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> C

    func body(content: Content) -> some View {
        #if os(macOS)
        if style.usesPopoverOnMac {
            content.popover(isPresented: $isPresented) {
                sheetContent()
                    .frame(
                        minWidth: macSize.width,
                        idealWidth: macSize.width,
                        minHeight: macSize.height,
                        idealHeight: macSize.height
                    )
            }
        } else {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .frame(
                        minWidth: macSize.width,
                        idealWidth: macSize.width,
                        minHeight: macSize.height,
                        idealHeight: macSize.height
                    )
            }
        }
        #else
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            sheetContent()
                .modifier(IOSSheetStyleModifier(style: style))
        }
        #endif
    }

    #if os(macOS)
    private var macSize: (width: CGFloat, height: CGFloat) {
        style.macFrameSize
    }
    #endif
}

// MARK: - Item-binding modifier

private struct AdaptivePresentationItemModifier<Item: Identifiable, C: View>: ViewModifier {
    @Binding var item: Item?
    let style: SheetStyle
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: (Item) -> C

    func body(content: Content) -> some View {
        #if os(macOS)
        // popover doesn't have an item: variant — bridge via isPresented
        if style.usesPopoverOnMac {
            content.popover(isPresented: itemPresented) {
                if let current = item {
                    sheetContent(current)
                        .frame(
                            minWidth: macSize.width,
                            idealWidth: macSize.width,
                            minHeight: macSize.height,
                            idealHeight: macSize.height
                        )
                }
            }
        } else {
            content.sheet(item: $item, onDismiss: onDismiss) { current in
                sheetContent(current)
                    .frame(
                        minWidth: macSize.width,
                        idealWidth: macSize.width,
                        minHeight: macSize.height,
                        idealHeight: macSize.height
                    )
            }
        }
        #else
        content.sheet(item: $item, onDismiss: onDismiss) { current in
            sheetContent(current)
                .modifier(IOSSheetStyleModifier(style: style))
        }
        #endif
    }

    #if os(macOS)
    private var itemPresented: Binding<Bool> {
        Binding(
            get: { item != nil },
            set: { if !$0 { item = nil } }
        )
    }

    private var macSize: (width: CGFloat, height: CGFloat) {
        style.macFrameSize
    }
    #endif
}

// MARK: - iOS detent styling (unchanged behavior)

private struct IOSSheetStyleModifier: ViewModifier {
    let style: SheetStyle

    func body(content: Content) -> some View {
        switch style {
        case .quickMenu:
            content
                .presentationDetents([detent])
                .presentationDragIndicator(.visible)
        case .selectionMenu, .picker, .form, .fullSheet:
            content
                .presentationDetents([detent])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
    }

    private var detent: PresentationDetent {
        switch style {
        case .quickMenu:              return .medium
        case .selectionMenu, .picker: return .fraction(0.65)
        case .form:                   return .fraction(0.85)
        case .fullSheet:              return .large
        }
    }
}

// MARK: - macOS frame sizes

#if os(macOS)
extension SheetStyle {
    var macFrameSize: (width: CGFloat, height: CGFloat) {
        switch self {
        case .quickMenu:     return (400, 320)
        case .selectionMenu: return (400, 420)
        case .picker:        return (400, 420)
        case .form:          return (480, 560)
        case .fullSheet:     return (520, 640)
        }
    }
}
#endif

// MARK: - Legacy support (kept for call sites not yet migrated)

extension View {
    /// Apply a standardized sheet presentation style.
    /// Prefer `.adaptivePresentation()` for new code.
    func sheetStyle(_ style: SheetStyle) -> some View {
        #if os(macOS)
        self.frame(
            minWidth: style.macFrameSize.width,
            idealWidth: style.macFrameSize.width,
            minHeight: style.macFrameSize.height,
            idealHeight: style.macFrameSize.height
        )
        #else
        modifier(IOSSheetStyleModifier(style: style))
        #endif
    }
}
