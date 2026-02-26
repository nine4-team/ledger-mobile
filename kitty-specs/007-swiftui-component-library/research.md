# Research: SwiftUI Component Library

## R1: Deferred Action Execution in SwiftUI Sheets

**Decision**: Use `@State private var pendingAction: (() -> Void)?` + `.onDismiss` on the `.sheet()` modifier.

**Rationale**: The RN `BottomSheetMenuList` stores a callback in a ref and executes it after the modal unmounts. In SwiftUI, `.sheet(isPresented:onDismiss:)` provides a clean hook. Store the action, set `isPresented = false`, and the `onDismiss` closure fires after the dismiss animation completes.

**Pattern**:
```swift
@State private var showMenu = false
@State private var pendingAction: (() -> Void)?

.sheet(isPresented: $showMenu, onDismiss: {
    pendingAction?()
    pendingAction = nil
}) {
    ActionMenuSheet(...)
}
```

**Alternatives considered**: `.onChange(of: showMenu)` — works but fires before animation completes; `.task` with `withAnimation` — overly complex.

## R2: Controlled vs. Uncontrolled Selection in SwiftUI

**Decision**: Use optional `Binding<Bool>?` with `@State` fallback.

**Rationale**: ItemCard and TransactionCard need to work in both controlled mode (parent manages selection) and uncontrolled mode (card manages its own state). SwiftUI doesn't have React's "defaultValue" concept natively, but we can check whether a binding was provided.

**Pattern**:
```swift
struct ItemCard: View {
    var isSelected: Binding<Bool>?
    @State private var internalSelected: Bool

    init(isSelected: Binding<Bool>? = nil, defaultSelected: Bool = false, ...) {
        self.isSelected = isSelected
        self._internalSelected = State(initialValue: defaultSelected)
    }

    private var selected: Bool {
        isSelected?.wrappedValue ?? internalSelected
    }

    private func toggleSelection() {
        if let binding = isSelected {
            binding.wrappedValue.toggle()
        } else {
            internalSelected.toggle()
        }
    }
}
```

**Alternatives considered**: Always require binding (forces parent to manage all state) — rejected because picker mode and standalone lists need simpler consumption.

## R3: Full-Screen Image Viewer with Gestures

**Decision**: Use `.fullScreenCover()` with `MagnificationGesture` + `DragGesture` + `TabView` for swipe.

**Rationale**: The spec explicitly justifies `.fullScreenCover()` as an exception to the bottom-sheet convention for ImageGallery. SwiftUI's gesture system handles pinch-to-zoom and pan natively.

**Pattern**:
```swift
.fullScreenCover(isPresented: $showGallery) {
    TabView(selection: $currentIndex) {
        ForEach(images.indices, id: \.self) { index in
            ZoomableImage(url: images[index].url)
                .tag(index)
        }
    }
    .tabViewStyle(.page(indexDisplayMode: .automatic))
}
```

`ZoomableImage` wraps `AsyncImage` with `@GestureState` for scale and offset, `MagnificationGesture` for pinch, `DragGesture` for pan, and double-tap to toggle zoom.

**Alternatives considered**: UIKit's `UIScrollView` via `UIViewRepresentable` — works well but adds UIKit bridging complexity; third-party zoom libraries — rejected per no-extra-dependencies decision.

## R4: BulkSelectionBar Placement

**Decision**: `.safeAreaInset(edge: .bottom)` with animation.

**Rationale**: The bulk selection bar needs to push list content up when it appears (not overlap). `.safeAreaInset` automatically adjusts scroll view insets. Wrap in `if selectedCount > 0` with `.animation(.default)` for smooth appear/disappear.

**Pattern**:
```swift
List { ... }
    .safeAreaInset(edge: .bottom) {
        if selectionManager.selectedCount > 0 {
            BulkSelectionBar(
                selectedCount: selectionManager.selectedCount,
                onBulkActions: { ... },
                onClear: { selectionManager.clearSelection() }
            )
            .transition(.move(edge: .bottom))
        }
    }
    .animation(.default, value: selectionManager.selectedCount > 0)
```

**Alternatives considered**: `.overlay(alignment: .bottom)` — doesn't push content up, causes overlap; `.toolbar(content:) .bottomBar` — limited customization.

## R5: ActionMenuSheet Submenu Expansion

**Decision**: `@State var expandedItemKey: String?` with `DisclosureGroup`-style inline expansion.

**Rationale**: Only one submenu can be open at a time. Tapping a menu item with subactions toggles its expansion (closing any previously expanded item). Selected subaction shows a checkmark.

**Pattern**: Custom `VStack` with animated expansion (not `DisclosureGroup` — we need custom styling). Each menu item checks `expandedItemKey == item.key` to show/hide its subaction list.

## R6: SharedItemsList Mode Architecture

**Decision**: Single `SharedItemsList` view with mode-specific configuration via an enum.

**Rationale**: The three modes (standalone, embedded, picker) share 80% of their rendering logic. Splitting into three separate views would duplicate the list rendering, filtering, and selection logic. Instead, use a `ListMode` enum that configures behavior at key decision points.

**Pattern**:
```swift
enum ItemsListMode {
    case standalone(scopeConfig: ScopeConfig)
    case embedded(items: [ScopedItem], onItemPress: (String) -> Void)
    case picker(eligibilityCheck: (ScopedItem) -> Bool, onAddSingle: (ScopedItem) -> Void)
}
```

The view switches on mode for: data source, footer bar, item press behavior, and header controls.

**Alternatives considered**: Protocol-based with three conforming types — cleaner separation but significant code duplication; Generic view with type parameters — over-engineered for three concrete modes.

## R7: Transaction Badge Color System

**Decision**: Extend `StatusColors` with transaction type colors if not already present.

**Research finding**: Current `StatusColors.swift` has budget status colors (met, in-progress, missed, overflow). Transaction badges need:
- Purchase: green
- Sale: blue
- Return: red
- To-inventory: brand primary
- Reimbursement/receipt: amber
- Needs-review: orange

**Action**: Check if these already exist in StatusColors. If not, add them as static properties following the same pattern. Use asset catalog colorsets for light/dark adaptation.

## R8: CurrencyFormatting Extraction

**Decision**: Create a shared `CurrencyFormatting` enum if `formatCents()` doesn't already exist in a reusable location.

**Research finding**: `BudgetDisplayCalculations.swift` already has cent-to-dollar formatting logic. Check if it's general enough to share across BudgetCategoryTracker, TransactionCard, and BulkSelectionBar. If it's budget-specific, extract a general `CurrencyFormatting.formatCents(_:)` that all components can use.

**Pattern**: `enum CurrencyFormatting` with static functions using `NumberFormatter` for locale-aware formatting.
