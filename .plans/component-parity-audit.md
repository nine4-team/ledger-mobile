# Component Parity Audit: React Native → SwiftUI

Audit date: 2025-02-25
Purpose: Complete cross-reference of RN and SwiftUI component libraries. Contains all context a manager agent needs to coordinate implementation.

Visual reference: `reference/screenshots/dark/` (17 screenshots showing established RN patterns)

---

## Coverage Summary

| Category | RN | SwiftUI Built | Needs Building | Not Needed |
|----------|:---:|:---:|:---:|:---:|
| Layout/Structure | 8 | 3 | 2 | 3 |
| Data Display | 12 | 4 | 8 | 0 |
| Input/Form | 7 | 4 | 3 | 0 |
| Modals/Sheets | 24 | 0 | 22 | 2 |
| Navigation | 2 | 1 | 0 | 1 |
| Feedback/Status | 7 | 0 | 7 | 0 |
| Selection/Bulk | 4 | 1 | 3 | 0 |
| Lists/Collections | 5 | 0 | 4 | 1 |
| Control Bars | 4 | 0 | 4 | 0 |
| Budget | 7 | 2 | 5 | 0 |
| Typography/Branding | 4 | 1 | 1 | 2 |
| **Total** | **84** | **16** | **59** | **9** |

---

## Convention Violation Found

### Bottom Sheet Menu → `.confirmationDialog()` Drift

**RN pattern (screenshot 15):** Bottom sheet slides up with dark overlay, item name as header, hierarchical action items (Open, Status >, Transaction >, Space >, Sell, Reassign, Delete) with icons and chevrons for submenus. Component: `BottomSheetMenuList`.

**SwiftUI current:** `ProjectsPlaceholderView` and `InventoryPlaceholderView` use `.confirmationDialog()` — on iPhone it's a plain action sheet (no header/icons/submenus), on iPad it's a floating popover (completely wrong).

**Fix:** Replace with `.sheet()` + `ActionMenuSheet` content. Blocked on building the `ActionMenuSheet` equivalent.

**Convention now documented in CLAUDE.md** — bottom sheet first, `.confirmationDialog` for destructive-only, no `.popover()`.

---

## Screenshot Map

Each screenshot and what components/patterns it demonstrates:

| Screenshot | Shows |
|---|---|
| `01_projects_list_.png` | ProjectCard (image, name, client, BudgetProgressPreview), tab bar, FAB (+) |
| `02_projects_list_archived.png` | ProjectCard in archived state, SegmentedControl (Active/Archived) |
| `03_project_detail_budget.png` | ScrollableTabBar, BudgetCategoryTracker rows, ProgressBar with overflow, CategoryRow |
| `04a_project_detail_items.png` | ItemCard, GroupedItemCard, ItemsListControlBar (search/sort/filter/add), SelectorCircle |
| `04b_project_detail_items.png` | ItemCard alternate state |
| `05_project_detail_transactions.png` | TransactionCard rows |
| `06_project_detail_spaces.png` | SpaceCard with image |
| `07_transaction_detail.png` | TitledCard, DetailRow, Badge (status), CollapsibleSection (checklist), MediaGallerySection |
| `08_transaction_detail_scrolled.png` | Same screen scrolled — more DetailRows |
| `09_item_detail.png` | CollapsibleSection (Images, Notes, Details), ThumbnailGrid, DetailRow |
| `10_item_detail_scrolled.png` | Same screen scrolled |
| `11_space_detail_1.png` | SpaceCard detail, image, notes |
| `12_space_detail_2.png` | Space detail alternate |
| `13_settings_presets_budget.png` | Settings list, CategoryRow-style rows |
| `14_settings_presets_vendors.png` | Settings list variant |
| `15_bottom_sheet_menu.png` | **BottomSheetMenuList** — hierarchical action menu with icons and chevrons |
| `inventory_screen.png` | ItemCard with thumbnail/metadata, ItemsListControlBar, SelectorCircle, bookmark icon |

---

## Dependency Graph & Build Order

### Direct Dependencies (component → what it uses)

```
ItemCard → [BottomSheetMenuList, SelectorCircle]
GroupedItemCard → [ItemCard, SelectorCircle]
ProjectCard → [ImageCard, BudgetProgressPreview]
TransactionCard → [BottomSheetMenuList, SelectorCircle]
SpaceCard → [ImageCard, ProgressBar]
BottomSheetMenuList → [BottomSheet]
FormBottomSheet → [BottomSheet, AppButton]
MediaGallerySection → [BottomSheetMenuList, ImageGallery, ThumbnailGrid, TitledCard, Card]
BulkSelectionBar → [AppButton]
ListControlBar → [AppButton, ListStateControls]
ItemsListControlBar → [ListControlBar]
BudgetCategoryTracker → [ProgressBar]
BudgetProgressPreview → [ProgressBar]
BudgetProgressDisplay → [AppButton, BudgetCategoryTracker]
SharedItemsList → [ItemsListControlBar, GroupedItemCard, ItemCard, FilterMenu, SortMenu, BulkSelectionBar, BottomSheetMenuList, modals/*]
SharedTransactionsList → [ListControlBar, FilterMenu, SortMenu, TransactionCard, BottomSheetMenuList]
```

### Reverse Dependencies (component ← what depends on it)

```
SelectorCircle ← [ItemCard, GroupedItemCard, TransactionCard, SharedItemsList, SharedTransactionsList]
ProgressBar ← [SpaceCard, BudgetCategoryTracker, BudgetProgressPreview]
BottomSheet ← [BottomSheetMenuList, FormBottomSheet, SharedItemsList, SharedTransactionsList]
BottomSheetMenuList ← [ItemCard, TransactionCard, MediaGallerySection, SharedItemsList, SharedTransactionsList]
ImageCard ← [ProjectCard, SpaceCard]
BudgetProgressPreview ← [ProjectCard]
BudgetCategoryTracker ← [BudgetProgressDisplay]
ItemCard ← [GroupedItemCard, SharedItemsList]
ListControlBar ← [ItemsListControlBar, SharedTransactionsList]
GroupedItemCard ← [SharedItemsList]
FilterMenu ← [SharedItemsList, SharedTransactionsList]
SortMenu ← [SharedItemsList, SharedTransactionsList]
ThumbnailGrid ← [MediaGallerySection]
ImageGallery ← [MediaGallerySection]
```

### Build Tiers (topological sort)

Components must be built in this order — each tier depends only on prior tiers.

**Tier 0 — Leaf components (no project dependencies).** Already built in SwiftUI: Card, TitledCard, Badge, DetailRow, ProgressBar, SelectorCircle, AppButton, FormField, SegmentedControl, CollapsibleSection, BudgetProgressView.

**Tier 1 — Depends on Tier 0 only:**
- ImageCard
- SpaceCard (needs ImageCard, ProgressBar ✅)
- BudgetCategoryTracker (needs ProgressBar ✅)
- BudgetProgressPreview (needs ProgressBar ✅)
- BottomSheet (SwiftUI: `.sheet()` + `.presentationDetents()` — no custom component needed, just a convention)
- FormBottomSheet → `FormSheet` (needs AppButton ✅)
- CategoryRow
- BulkSelectionBar (needs AppButton ✅)
- ListStateControls
- ThumbnailGrid
- ImageGallery
- LoadingScreen, ErrorRetryView, StatusBanner

**Tier 2 — Depends on Tier 0–1:**
- BottomSheetMenuList → `ActionMenuSheet` (needs BottomSheet convention)
- BudgetProgressDisplay (needs BudgetCategoryTracker)
- ListControlBar (needs ListStateControls)
- ProjectCard ⚠️ IN PROGRESS (needs ImageCard, BudgetProgressPreview)
- ItemCard (needs BottomSheetMenuList, SelectorCircle ✅)

**Tier 3 — Depends on Tier 0–2:**
- TransactionCard (needs BottomSheetMenuList, SelectorCircle ✅)
- GroupedItemCard (needs ItemCard, SelectorCircle ✅)
- MediaGallerySection (needs BottomSheetMenuList, ImageGallery, ThumbnailGrid, TitledCard ✅, Card ✅)
- ItemsListControlBar (needs ListControlBar)
- FilterMenu (needs BottomSheetMenuList)
- SortMenu (needs BottomSheetMenuList)

**Tier 4 — Depends on Tier 0–3:**
- SharedItemsList (needs ItemsListControlBar, GroupedItemCard, ItemCard, FilterMenu, SortMenu, BulkSelectionBar, BottomSheetMenuList)
- SharedTransactionsList (needs ListControlBar, FilterMenu, SortMenu, TransactionCard, BottomSheetMenuList)

**Tier 5 — Feature modals (depend on FormSheet + various pickers):**
- All `modals/*` components (EditItemDetailsModal, SetSpaceModal, ReassignToProjectModal, etc.)
- ProjectSelector, SpaceSelector, VendorPicker, MultiSelectPicker

---

## Already Built (SwiftUI ↔ RN match)

| SwiftUI Component | File | RN Equivalent | RN File |
|---|---|---|---|
| `Card` | `Components/Card.swift` | `Card.tsx` | `src/components/Card.tsx` |
| `TitledCard` | `Components/TitledCard.swift` | `TitledCard.tsx` | `src/components/TitledCard.tsx` |
| `CollapsibleSection` | `Components/CollapsibleSection.swift` | `CollapsibleSectionHeader.tsx` | `src/components/CollapsibleSectionHeader.tsx` |
| `Badge` | `Components/Badge.swift` | *(inline)* | — |
| `DetailRow` | `Components/DetailRow.swift` | `DetailRow.tsx` | `src/components/DetailRow.tsx` |
| `ProgressBar` | `Components/ProgressBar.swift` | `ProgressBar.tsx` | `src/components/ProgressBar.tsx` |
| `BudgetProgressView` | `Components/BudgetProgressView.swift` | `BudgetProgress.tsx` | `src/components/BudgetProgress.tsx` |
| `FormField` | `Components/FormField.swift` | `FormField.tsx` | `src/components/FormField.tsx` |
| `SegmentedControl` | `Components/SegmentedControl.swift` | `SegmentedControl.tsx` | `src/components/SegmentedControl.tsx` |
| `SelectorCircle` | `Components/SelectorCircle.swift` | `SelectorCircle.tsx` | `src/components/SelectorCircle.tsx` |
| `AppButton` | `Components/AppButton.swift` | `AppButton.tsx` | `src/components/AppButton.tsx` |

---

## In Progress (Phase 4 — another agent building these now)

| SwiftUI Target | RN Equivalent | Status |
|---|---|---|
| `ScrollableTabBar` | `ScreenTabs.tsx` | Step 2a |
| `ProjectCard` | `ProjectCard.tsx` | Step 2b |
| `ProjectsListView` | Projects screen | Step 3a |
| `ProjectDetailView` | Project detail shell | Step 3b |
| `BudgetTabView` | Budget tab content | Step 3c |
| 4 tab placeholders (Items, Transactions, Spaces, Accounting) | Tab content stubs | Step 3d |
| `ProjectListCalculations` | Business logic | Step 1a |
| `BudgetTabCalculations` | Business logic | Step 1b |

---

## Needs Building — Full Inventory

Every RN component that needs a SwiftUI equivalent, with source file, screenshot reference, and RN props interface.

### Data Display

#### ImageCard
- **RN source:** `src/components/ImageCard.tsx`
- **Screenshot:** Item/space detail screens
- **Used by:** ProjectCard, SpaceCard
- **Description:** Card with image area (configurable aspect ratio, placeholder) and content below.
- **RN props:** `imageUri`, `onPress`, `children`, `showPlaceholder`, `imageAspectRatio`

#### ItemCard
- **RN source:** `src/components/ItemCard.tsx`
- **Screenshots:** `inventory_screen.png`, `04a/b_project_detail_items.png`
- **Used by:** GroupedItemCard, SharedItemsList
- **Depends on:** BottomSheetMenuList, SelectorCircle ✅
- **Description:** Expandable item card with thumbnail, metadata lines (name, SKU, source, location, price), selection circle, bookmark toggle, context menu.
- **RN props:**
```typescript
{
  name: string;
  sku?: string;
  sourceLabel?: string;
  locationLabel?: string;
  notes?: string;
  priceLabel?: string;
  indexLabel?: string;
  statusLabel?: string;
  budgetCategoryName?: string;
  thumbnailUri?: string;
  stackSkuAndSource?: boolean;
  selected?: boolean;
  defaultSelected?: boolean;
  onSelectedChange?: (selected: boolean) => void;
  bookmarked?: boolean;
  onBookmarkPress?: () => void;
  onAddImagePress?: () => void;
  onMenuPress?: () => void;
  menuItems?: AnchoredMenuItem[];
  onPress?: () => void;
  onStatusPress?: () => void;
  headerAction?: React.ReactNode;
  warningMessage?: string;
}
```

#### GroupedItemCard
- **RN source:** `src/components/GroupedItemCard.tsx`
- **Screenshot:** `04a_project_detail_items.png`
- **Used by:** SharedItemsList
- **Depends on:** ItemCard, SelectorCircle ✅
- **Description:** Collapsible card grouping multiple ItemCards. Shows summary (name, count, total) when collapsed; expands to show individual ItemCards.
- **RN props:**
```typescript
{
  summary: { name, sku, sourceLabel, locationLabel, notes, thumbnailUri };
  countLabel?: string;
  totalLabel?: string;
  microcopyWhenCollapsed?: string;
  items: ItemCardProps[];
  expanded?: boolean;
  defaultExpanded?: boolean;
  onExpandedChange?: (expanded: boolean) => void;
  selected?: boolean;
  onSelectedChange?: (selected: boolean) => void;
  onPress?: () => void;
}
```

#### TransactionCard
- **RN source:** `src/components/TransactionCard.tsx`
- **Screenshot:** `05_project_detail_transactions.png`
- **Used by:** SharedTransactionsList
- **Depends on:** BottomSheetMenuList, SelectorCircle ✅
- **Description:** Transaction list item with source, amount, date, category badge, type badge, review indicator, selection, bookmark, context menu.
- **RN props:**
```typescript
{
  id: string;
  source: string;
  amountCents: number | null;
  transactionDate?: string;
  notes?: string;
  budgetCategoryName?: string;
  transactionType?: 'purchase' | 'return' | 'sale' | 'to-inventory';
  needsReview?: boolean;
  reimbursementType?: 'owed-to-client' | 'owed-to-company';
  purchasedBy?: string;
  itemCount?: number;
  hasEmailReceipt?: boolean;
  status?: 'pending' | 'completed' | 'canceled';
  selected?: boolean;
  onSelectedChange?: (selected: boolean) => void;
  bookmarked?: boolean;
  onBookmarkPress?: () => void;
  menuItems?: AnchoredMenuItem[];
  onPress?: () => void;
}
```

#### SpaceCard
- **RN source:** `src/components/SpaceCard.tsx`
- **Screenshot:** `06_project_detail_spaces.png`
- **Depends on:** ImageCard, ProgressBar ✅
- **Description:** Space card with image, item count, checklist progress, optional notes.
- **RN props:**
```typescript
{
  name: string;
  itemCount: number;
  primaryImage?: AttachmentRef | null;
  checklists?: Checklist[] | null;
  notes?: string | null;
  showNotes?: boolean;
  onPress: () => void;
  onMenuPress?: () => void;
}
```

#### ThumbnailGrid
- **RN source:** `src/components/ThumbnailGrid.tsx`
- **Screenshot:** `09_item_detail.png` (Images section)
- **Used by:** MediaGallerySection
- **Description:** Grid of image thumbnails with overlay badges (primary indicator, count).

#### DraggableCard
- **RN source:** `src/components/DraggableCard.tsx`
- **Description:** Card with drag handle for reordering. Used in category reordering.
- **RN props:** `title`, `disabled`, `isActive`, `dragHandleProps`, `right`

#### InfoCard
- **RN source:** `src/components/InfoCard.tsx`
- **Description:** Information display card.

### Modals/Sheets — Base Components

#### BottomSheet → `.sheet()` convention
- **RN source:** `src/components/BottomSheet.tsx`
- **Screenshot:** `15_bottom_sheet_menu.png`
- **SwiftUI approach:** Not a custom component — use `.sheet()` + `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`. Convention documented in CLAUDE.md.
- **RN props:**
```typescript
{
  visible: boolean;
  onRequestClose: () => void;
  onDismiss?: () => void;
  containerStyle?: ViewStyle;
  children: React.ReactNode;
}
```

#### FormBottomSheet → `FormSheet`
- **RN source:** `src/components/FormBottomSheet.tsx`
- **Screenshot:** *(used across all edit flows)*
- **Depends on:** AppButton ✅
- **Description:** Reusable sheet scaffold — title, optional description, content area, primary + secondary action buttons, optional error message.
- **RN props:**
```typescript
{
  visible: boolean;
  onRequestClose: () => void;
  title: string;
  description?: string;
  children: React.ReactNode;
  primaryAction: { title: string; onPress: () => void | Promise<void>; loading?: boolean; disabled?: boolean };
  secondaryAction?: { title: string; onPress: () => void; disabled?: boolean };
  error?: string;
}
```

#### MultiStepFormBottomSheet
- **RN source:** `src/components/MultiStepFormBottomSheet.tsx`
- **Description:** Form scaffold with step indicator (e.g., "Step 2 of 3"). Same as FormBottomSheet plus `currentStep` and `totalSteps`.

#### BottomSheetMenuList → `ActionMenuSheet`
- **RN source:** `src/components/BottomSheetMenuList.tsx`
- **Screenshot:** `15_bottom_sheet_menu.png`
- **Used by:** ItemCard, TransactionCard, MediaGallerySection, SharedItemsList, SharedTransactionsList
- **Description:** Hierarchical action menu in a bottom sheet. Items have icons, labels, optional chevron for submenus. Submenus expand inline with checkmark selection state. Supports multi-select mode (closeOnItemPress=false).
- **RN props:**
```typescript
{
  visible: boolean;
  onRequestClose: () => void;
  items: AnchoredMenuItem[];
  title?: string;
  showLeadingIcons?: boolean;
  activeSubactionKey?: string;
  hideDefaultLabel?: boolean;
  maxContentHeight?: number;
  closeOnSubactionPress?: boolean;
  closeOnItemPress?: boolean;
}

// Menu item type:
type AnchoredMenuItem = {
  key?: string;
  label: string;
  onPress?: () => void;
  icon?: string;
  subactions?: { key: string; label: string; onPress: () => void; icon?: string }[];
  selectedSubactionKey?: string;
  destructive?: boolean;
  actionOnly?: boolean;
};
```

#### FilterMenu
- **RN source:** `src/components/FilterMenu.tsx`
- **Depends on:** BottomSheetMenuList
- **Description:** Thin wrapper around BottomSheetMenuList for filter-specific usage.
- **RN props:** `{ visible, onRequestClose, items: AnchoredMenuItem[], title? }`

#### SortMenu
- **RN source:** `src/components/SortMenu.tsx`
- **Depends on:** BottomSheetMenuList
- **Description:** Thin wrapper around BottomSheetMenuList for sort-specific usage.
- **RN props:** `{ visible, onRequestClose, items: AnchoredMenuItem[], title?, activeSubactionKey? }`

#### ImageGallery
- **RN source:** `src/components/ImageGallery.tsx`
- **Used by:** MediaGallerySection
- **Description:** Full-screen image viewer with pinch/pan zoom, swipe navigation between images. Uses `.fullScreenCover()` in SwiftUI (justified exception to bottom-sheet rule).
- **RN props:** `{ images, initialIndex, visible, onRequestClose, onPinToggle }`

#### MultiSelectPicker
- **RN source:** `src/components/MultiSelectPicker.tsx`
- **Description:** Card-based multi/single-select picker with options grid.
- **RN props:** `{ value, options, onChange, multiSelect, label, helperText }`

### Modals/Sheets — Feature Modals

All in `src/components/modals/`. Each wraps `FormBottomSheet` with domain-specific content.

| RN Component | RN Source | What It Does |
|---|---|---|
| `EditItemDetailsModal` | `modals/EditItemDetailsModal.tsx` | Edit item name, SKU, etc. |
| `EditTransactionDetailsModal` | `modals/EditTransactionDetailsModal.tsx` | Edit transaction details |
| `EditSpaceDetailsModal` | `modals/EditSpaceDetailsModal.tsx` | Edit space metadata |
| `EditNotesModal` | `modals/EditNotesModal.tsx` | Edit notes |
| `EditChecklistModal` | `modals/EditChecklistModal.tsx` | Edit checklist |
| `SetSpaceModal` | `modals/SetSpaceModal.tsx` | Assign item to a space |
| `ReassignToProjectModal` | `modals/ReassignToProjectModal.tsx` | Reassign items to another project |
| `SellToProjectModal` | `modals/SellToProjectModal.tsx` | Sell item to project + category picker |
| `SellToBusinessModal` | `modals/SellToBusinessModal.tsx` | Sell item outside project |
| `TransactionPickerModal` | `modals/TransactionPickerModal.tsx` | Select/link a transaction |
| `ReturnTransactionPickerModal` | `modals/ReturnTransactionPickerModal.tsx` | Link to return transaction |
| `ProjectPickerList` | `modals/ProjectPickerList.tsx` | Project selection list |
| `CategoryPickerList` | `modals/CategoryPickerList.tsx` | Category selection list |
| `SpacePickerList` | `modals/SpacePickerList.tsx` | Space selection list |

### Input/Form

| RN Component | RN Source | What It Does |
|---|---|---|
| `ProjectSelector` | `src/components/ProjectSelector.tsx` | Project dropdown with search (opens bottom sheet) |
| `SpaceSelector` | `src/components/SpaceSelector.tsx` | Space dropdown |
| `VendorPicker` | `src/components/VendorPicker.tsx` | Vendor selection |

### Selection/Bulk

#### BulkSelectionBar
- **RN source:** `src/components/BulkSelectionBar.tsx`
- **Depends on:** AppButton ✅
- **Description:** Bottom bar showing selected count, optional total, bulk action button, clear selection button.
- **RN props:** `{ selectedCount: number; totalCents?: number; onBulkActionsPress: () => void; onClearSelection: () => void }`

#### ListSelectAllRow
- **RN source:** `src/components/ListSelectAllRow.tsx`
- **Description:** Row with select-all checkbox and label.
- **RN props:** `{ disabled, onPress, checked, label }`

#### ListSelectionInfo
- **RN source:** `src/components/ListSelectionInfo.tsx`
- **Description:** Text info about current selection state.
- **RN props:** `{ text, onPress }`

### Lists/Collections

#### SharedItemsList
- **RN source:** `src/components/SharedItemsList.tsx`
- **Depends on:** ItemsListControlBar, GroupedItemCard, ItemCard, FilterMenu, SortMenu, BulkSelectionBar, BottomSheetMenuList, 6 modals
- **Description:** Complex reusable items list supporting standalone mode (fetches its own data), embedded mode (receives items), and picker mode (for item selection flows). Handles grouping, selection, filtering, sorting, bulk actions.
- **RN props:**
```typescript
{
  // Standalone mode
  scopeConfig?: ScopeConfig;
  listStateKey?: string;
  refreshToken?: number;
  // Embedded mode
  embedded?: boolean;
  manager?: UseItemsManagerReturn;
  items?: ScopedItem[];
  bulkActions?: BulkAction[];
  onItemPress?: (id: string) => void;
  getItemMenuItems?: (item: ScopedItem) => AnchoredMenuItem[];
  emptyMessage?: string;
  // Picker mode
  picker?: boolean;
  eligibilityCheck?: ItemEligibilityCheck;
  onAddSingle?: (item: ScopedItem | Item) => void | Promise<void>;
  addedIds?: Set<string>;
  onAddSelected?: () => void | Promise<void>;
  addButtonLabel?: string;
}
```

#### SharedTransactionsList
- **RN source:** `src/components/SharedTransactionsList.tsx`
- **Depends on:** ListControlBar, FilterMenu, SortMenu, TransactionCard, BottomSheetMenuList
- **Description:** Transaction list with same filtering/sorting/selection pattern as SharedItemsList.

#### DraggableCardList
- **RN source:** `src/components/DraggableCardList.tsx`
- **Description:** Generic drag-to-reorder list. SwiftUI equivalent: `List` with `.onMove(perform:)`.

#### MediaGallerySection
- **RN source:** `src/components/MediaGallerySection.tsx`
- **Screenshot:** `09_item_detail.png`
- **Depends on:** BottomSheetMenuList, ImageGallery, ThumbnailGrid, TitledCard ✅, Card ✅
- **Description:** Section managing image/PDF attachments — add, remove, set primary, full-screen viewer.
- **RN props:**
```typescript
{
  title: string;
  attachments: AttachmentRef[];
  maxAttachments?: number;
  allowedKinds?: AttachmentKind[];
  onAddAttachment?: (localUri: string, kind: AttachmentKind) => void | Promise<void>;
  onRemoveAttachment?: (attachment: AttachmentRef) => void | Promise<void>;
  onSetPrimary?: (attachment: AttachmentRef) => void | Promise<void>;
  size?: 'sm' | 'md' | 'lg';
  emptyStateMessage?: string;
}
```

### Control Bars

#### ListControlBar
- **RN source:** `src/components/ListControlBar.tsx`
- **Depends on:** AppButton ✅, ListStateControls
- **Description:** Generic search bar + action buttons.
- **RN props:**
```typescript
{
  search: string;
  onChangeSearch: (value: string) => void;
  actions: { title: string; onPress: () => void; variant: 'primary' | 'secondary'; iconName?: string; disabled?: boolean; active?: boolean }[];
  leftElement?: React.ReactNode;
  showSearch?: boolean;
}
```

#### ItemsListControlBar
- **RN source:** `src/components/ItemsListControlBar.tsx`
- **Depends on:** ListControlBar
- **Description:** Items-specific control bar — search, sort, filter, add.

#### ItemPickerControlBar
- **RN source:** `src/components/ItemPickerControlBar.tsx`
- **Description:** Item picker control bar — search, select-all, add selected button.

#### ListStateControls
- **RN source:** `src/components/ListStateControls.tsx`
- **Description:** Search input portion of control bars.

### Budget

#### BudgetCategoryTracker
- **RN source:** `src/components/budget/BudgetCategoryTracker.tsx`
- **Screenshot:** `03_project_detail_budget.png`
- **Depends on:** ProgressBar ✅
- **Description:** Category-level budget tracker with title, spent/remaining labels, progress bar.

#### BudgetProgressDisplay
- **RN source:** `src/components/budget/BudgetProgressDisplay.tsx`
- **Screenshot:** `03_project_detail_budget.png`
- **Depends on:** BudgetCategoryTracker
- **Description:** Full budget progress summary with multiple category trackers.

#### BudgetProgressPreview
- **RN source:** `src/components/budget/BudgetProgressPreview.tsx`
- **Screenshot:** `01_projects_list_.png` (inside ProjectCard)
- **Depends on:** ProgressBar ✅
- **Description:** Compact budget preview showing pinned category name, spent/remaining, and progress bar. Used inside ProjectCard.

#### CategoryRow
- **RN source:** `src/components/budget/CategoryRow.tsx`
- **Screenshot:** `03_project_detail_budget.png`
- **Description:** Single budget category row.

#### ArchivedCategoryRow
- **RN source:** `src/components/budget/ArchivedCategoryRow.tsx`
- **Description:** Archived category row variant.

### Feedback/Status

#### StatusBanner
- **RN source:** `src/components/StatusBanner.tsx`
- **Description:** Sticky banner (error/warning/info) with optional action buttons.
- **RN props:** `{ message: string; variant?: 'error' | 'warning' | 'info'; bottomOffset?: number; actions?: ReactNode }`

#### ErrorRetryView
- **RN source:** `src/components/ErrorRetryView.tsx`
- **Description:** Error message with retry button and offline indicator.
- **RN props:** `{ message: string; onRetry?: () => void; isOffline?: boolean }`

#### LoadingScreen
- **RN source:** `src/components/LoadingScreen.tsx`
- **Description:** Full-screen loading indicator with message.

#### NetworkStatusBanner
- **RN source:** `src/components/NetworkStatusBanner.tsx`
- **Description:** Offline/slow connection banner. Wraps StatusBanner.

#### SyncStatusBanner
- **RN source:** `src/components/SyncStatusBanner.tsx`
- **Description:** Sync status display.

#### SyncIndicator
- **RN source:** `src/components/SyncIndicator.tsx`
- **Description:** Small sync status indicator.

#### OfflineUX (3 utilities)
- **RN source:** `src/components/OfflineUX.tsx`
- **Description:** OfflineLoadingOverlay, StaleIndicator, QueuedWritesBadge.

### Layout/Structure

#### Screen
- **RN source:** `src/components/Screen.tsx`
- **SwiftUI approach:** NavigationStack + .navigationTitle + .toolbar handles this. May need a reusable `ScreenContainer` if styling diverges from system defaults.

#### FormActions → `safeAreaInset` pattern
- **RN source:** `src/components/FormActions.tsx`
- **SwiftUI approach:** `.safeAreaInset(edge: .bottom)` or `.toolbar` with `ToolbarItem(placement: .bottomBar)`.

---

## Not Needed in SwiftUI

| RN Component | SwiftUI Equivalent |
|---|---|
| `AppText` | `Text` + `Typography` view modifiers in `Theme/` |
| `AppScrollView` | `ScrollView` (native) |
| `StickyHeader` | `Section` headers in `List` (sticky by default) |
| `TopHeader` | `.navigationTitle` + `.toolbar` |
| `AnchoredMenu` / `AnchoredMenuList` | SwiftUI `Menu` / `.contextMenu` |
| `InfoButton` | `.alert()` with informational content |
| `ItemConflictDialog` | `.alert()` with destructive action |
| `GoogleMark` / `BrandLogo` | Asset catalog images |
| `SpaceCardSkeleton` | `.redacted(reason: .placeholder)` |
| Import/Parsing (3 files) | Phase-specific, not shared UI |

---

## Actions Taken

1. **Done:** Modal & Sheet Presentation convention added to `CLAUDE.md`
2. **Fix needed:** Replace `.confirmationDialog()` in `ProjectsPlaceholderView` and `InventoryPlaceholderView` (blocked on `ActionMenuSheet`)
3. **This audit should be referenced** when planning any phase that builds components or screens
