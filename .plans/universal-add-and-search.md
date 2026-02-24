# Universal Add & Search Implementation Plan

## Overview
Implement three interconnected features:
1. **Tab bar restructuring** — add Universal Add button to tab bar
2. **Universal Add Transaction flow** — single-screen progressive disclosure form
3. **Universal Search** — account-level search modal with tabs for Items, Transactions, Spaces

---

## Phase 1: Tab Bar Restructuring
**Effort: Small | Files: 1-2**

### Changes
- **`app/(tabs)/_layout.tsx`**: Add a new "Add" tab in position 0 (before Projects)
  - Brand color (`#987e55`) filled circle with white `+` icon
  - This tab does NOT navigate to a screen — tapping it opens a `BottomSheetMenuList` with two options: "Add Item" and "Add Transaction"
  - Use a custom `tabBarButton` to intercept the press and show the sheet instead of navigating
  - Tab order becomes: **Add | Projects | Inventory | Settings**

### Implementation Detail
- Use `Tabs.Screen` with `options.tabBarButton` to render a custom pressable that opens the bottom sheet instead of navigating
- Create a dummy screen file (e.g., `app/(tabs)/add.tsx`) that returns null — Expo Router requires a file for each tab, but it will never be shown
- The bottom sheet uses the existing `BottomSheetMenuList` component
- "Add Transaction" → `router.push('/transactions/new-universal')` (new screen)
- "Add Item" → `router.push('/items/new')` (existing screen, may need scope param adjustments for account-level context)

### Header Changes
- **Projects (`app/(tabs)/index.tsx`)**: Replace `onPressAdd` with a search icon in `headerRight`. Move the project creation into a control bar within the Spaces tab (matching the pattern already used in spaces).
- **Inventory (`app/(tabs)/screen-two.tsx`)**: Add search icon via `headerRight`
- **Settings (`app/(tabs)/settings.tsx`)**: Replace the logout button in `headerRight` with a search icon. Move sign-out to the bottom of the General tab content.

---

## Phase 2: Universal Add Transaction Flow
**Effort: Large | Files: 3-5 new, 2-3 modified**

### New Screen: `app/transactions/new-universal.tsx`

Single screen with progressive disclosure. Sections reveal as the user makes choices.

#### Step 1: Transaction Type
- Two large tappable cards: **Purchase** | **Return**
- Once selected, shows as a compact chip/row at top, next section reveals below

#### Step 2: Destination
- Reuse `ProjectPickerList` component inside the form (not in a modal — rendered inline)
- Shows "Business Inventory" as first option, then project list
- Once selected, shows as compact chip/row, next section reveals

#### Step 3a: Purchase Branch — Channel
- Two tappable options: **Online** | **In-Store**
- If **Online**: Show import options (Wayfair, Amazon, Create Manually)
  - Wayfair/Amazon navigate to existing import screens: `/project/[projectId]/import-amazon`, `/project/[projectId]/import-wayfair`
  - "Create Manually" reveals the details form (step 4)
- If **In-Store**: Reveals details form (step 4)

#### Step 3b: Return Branch — Link Items
- Prompt: "Link items to this return?"
- Two options: **Yes** | **Skip**
- If **Yes**: Show `SharedItemsList` in picker mode, scoped to the selected destination
  - On selection, validate budget categories match — if conflict, show `Alert.alert()` blocking
  - On valid selection, auto-fill: budget category, tax rate, source from items
- If **Skip**: Show manual fields for budget category, source, tax rate

#### Step 4a: Purchase Details Form
- Date (date picker)
- Source (text input)
- Notes (text input)
- Images — "Other Images" with prompt to photograph items/tags for later item creation
- **Create** button at bottom

#### Step 4b: Return Details Form
- Purchasing Card or Gift Card? (toggle/selector)
- Source (text input, may be pre-filled from items)
- Amount (currency input)
- Budget Category (picker, may be pre-filled)
- Email Receipt (text input)
- Receipt Upload (image picker)
- Purchased By (picker)
- **Create** button at bottom

#### On Create
- Call `createTransaction()` (fire-and-forget, offline-first)
- Navigate to `/transactions/[id]` detail screen
- Pass a `showNextSteps=true` param to trigger the Next Steps card

### State Management
- Use `useReducer` or `useState` for form state with a `step` tracker
- Each completed step stores its value and collapses to a summary row
- Changing a previous step resets all subsequent steps
- Subtle progress bar at top (thin line that fills proportionally)

---

## Phase 3: Gamified Next Steps Card
**Effort: Medium | Files: 2-3 new, 1-2 modified**

### New Component: `app/transactions/[id]/sections/NextStepsSection.tsx`

Appears at the top of the transaction detail screen when the transaction was just created (controlled by nav param or by detecting missing fields).

#### Next Steps Logic
Analyze the transaction and generate a list of actionable items:
- "Add a receipt" — if `receiptImages` is empty
- "Categorize this transaction" — if `budgetCategoryId` is null
- "Enter the amount" — if `amountCents` is null/0
- "Set tax rate" — if `taxRatePct` is null and budget category is itemized
- "Add items" — always shown if `itemIds` is empty (with count if images were uploaded: "You uploaded 3 photos — create items from them?")
- "Set purchased by" — if `purchasedBy` is null
- "Complete email receipt" — if `hasEmailReceipt` is null

#### UI Design
- Card at top of detail screen with slight brand-color accent
- Small progress ring (e.g., "3/6 complete")
- Each step is a row with:
  - Checkbox (filled when complete)
  - Label
  - Tap action (scrolls to relevant section or opens the edit modal)
- Steps disappear (with animation) as completed
- Card auto-hides when all steps are done

### Modifications
- **`app/transactions/[id]/index.tsx`**: Accept `showNextSteps` param, render `NextStepsSection` at top when present or when transaction has incomplete fields
- Consider: should NextStepsSection always show for incomplete transactions, or only for newly created ones? Recommend: always show if there are incomplete fields, but make it collapsible/dismissible.

---

## Phase 4: Universal Search
**Effort: Medium-Large | Files: 2-4 new, 3 modified**

### New Screen: `app/search.tsx`

Full-screen modal (presented modally, slides up).

#### Layout
- Search bar at top, auto-focused on mount
- Three tabs below: **Items** | **Transactions** | **Spaces**
- Results filtered by search query, tab persists query across switches

#### Items Tab
- Uses `SharedItemsList` in embedded mode
- Items filtered by search query against name, source, SKU
- Kebab menus and bottom sheets work as-is (existing item actions)
- Scoped to entire account (inventory scope)

#### Transactions Tab
- Uses existing `TransactionCard` components in a FlatList
- Filtered by source, notes, amount
- Tap navigates to transaction detail

#### Spaces Tab
- Uses existing `SpaceCard` components
- Filtered by name
- Tap navigates to space detail

### Search Implementation
- Use existing search index infrastructure (`src/search-index/`) if available
- Otherwise, subscribe to account-level collections and filter client-side
- Debounced search input (300ms)

### Navigation Integration
- All three main screens (Projects, Inventory, Settings) get a search icon in `headerRight`
- Tapping any of them pushes `/search` as a modal

---

## Implementation Order

1. **Phase 1: Tab bar** — smallest change, foundational for everything else
2. **Phase 2: Universal Add Transaction** — core new functionality
3. **Phase 3: Next Steps Card** — enhances the post-creation experience
4. **Phase 4: Universal Search** — independent feature, can be done last

---

## Key Reuse Points
- `BottomSheetMenuList` — Add button action sheet
- `ProjectPickerList` — destination selector in transaction flow
- `SharedItemsList` (picker mode) — item linking in return flow
- `SharedItemsList` (embedded mode) — search results for items
- `TransactionCard` — search results for transactions
- `SpaceCard` — search results for spaces
- `BottomSheet` — various modals throughout
- `createTransaction()` — existing service function
- `computeTransactionCompleteness()` — informs Next Steps logic
- Existing invoice import screens — linked from Online purchase flow

## Files to Create
- `app/(tabs)/add.tsx` — dummy tab screen
- `app/transactions/new-universal.tsx` — universal add transaction screen
- `app/transactions/[id]/sections/NextStepsSection.tsx` — gamified next steps
- `app/search.tsx` — universal search modal

## Files to Modify
- `app/(tabs)/_layout.tsx` — add tab, reorder
- `app/(tabs)/index.tsx` — header change (plus → search)
- `app/(tabs)/screen-two.tsx` — header change (add search)
- `app/(tabs)/settings.tsx` — header change (logout → search), sign out to General tab
- `app/transactions/[id]/index.tsx` — integrate NextStepsSection
