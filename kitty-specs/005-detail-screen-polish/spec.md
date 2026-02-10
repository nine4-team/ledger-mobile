# Feature Specification: Detail Screen Polish

**Feature Branch**: `005-detail-screen-polish`
**Created**: 2026-02-10
**Status**: Draft
**Input**: Fix regressions, omissions, and architectural mistakes from 004-detail-screen-normalization. Addresses 8 specific issues across transaction detail, item detail, space detail, and the shared item list component.

## Background: What Went Wrong in 004

Feature 004 (Detail Screen Normalization) completed 6 work packages: space consolidation, SectionList migration, shared items management, and detail row extraction. However, it introduced regressions and left significant gaps. This feature fixes those issues.

### Spec-Level Failures in 004

The following were never specified and should have been:

1. **Item list component choice**: The 004 spec created a new `ItemsSection` component instead of reusing the existing `SharedItemsList` component (used in the project items tab and inventory items tab). `SharedItemsList` already had grouped item cards, proper bulk selection with a bottom bar + bottom sheet, selector circles, and status badges. The 004 spec's research phase *analyzed* `SharedItemsList` but then decided to build a new abstraction, reinventing the wheel with inferior results.
2. **Item detail top card content**: The spec defined item detail sections (hero, media, notes, details) but never specified what the hero/top card should display. It should show the item description, the linked transaction (as navigable text showing source and amount), and the assigned space.
3. **Tax and Details combination**: The spec preserved Tax/Itemization and Details as separate collapsible sections in transaction detail. They should be a single section.
4. **Linked transaction text format**: The spec never specified how linked transactions should be displayed in item detail. Currently shows the transaction ID; should show "Source - $Amount".
5. **Section spacing normalization**: The spec required "consistent collapsible sections" but never defined the inter-section gap value. Each screen ended up with different gaps (transaction: 10px, space: 4px, item: varies).
6. **Move items placement**: The spec said "preserve existing functionality," which kept the Move Item form inline in item detail. It belongs in the kebab menu.
7. **Bulk controls pattern**: The spec never specified the UI pattern for bulk actions. `ItemsSection` invented inline buttons instead of matching `SharedItemsList`'s proven pattern (sticky bottom bar with count + "Bulk Actions" button that opens a bottom sheet).
8. **Space detail default expanded states**: The spec set media and items both expanded by default. Only images should be expanded.

### Implementation-Level Failures in 004

These should have been caught during implementation or review:

1. **Duplicate card titles**: `CollapsibleSectionHeader` renders "DETAILS" (uppercase), then the inner `Card`/`TitledCard` renders "Details" again inside the section content. This produces a double title.
2. **Selector toggle logic**: The bulk select button calls `selectAll` but does not toggle to deselect when all items are already selected.
3. **Missing ItemCard props**: `ItemCard` supports `selected`, `statusLabel`, and `onSelectedChange` props, but `ItemsSection` does not pass them through. The component has the capability; the integration missed it.
4. **Inconsistent section gaps**: No one normalized the `contentContainerStyle.gap` value across screens after migrating them all to SectionList.

## User Scenarios & Testing

### User Story 1 - Correct Item List Component (Priority: P1)

As a user viewing items on any screen (transaction detail, space detail), I see the same item list experience I already have in the project items tab and inventory items tab. Items are displayed using grouped cards. Each card shows a selector circle and status badge. Bulk selection uses a sticky bottom bar with a "Bulk Actions" button that opens a bottom sheet.

**Why this priority**: The item list is the most visibly broken component. It's missing key visual elements (selector, status badge), uses the wrong card component (plain `ItemCard` instead of `GroupedItemCard`), has broken toggle logic, and has a non-standard bulk actions UI. This affects every screen that shows items.

**Independent Test**: Navigate to transaction detail or space detail with multiple items. Verify the item list matches the existing behavior in the project items tab (grouped cards, selector circles, status badges, bottom bar bulk actions).

**Reference implementation**: The project items tab (`SharedItemsList` component) is the canonical reference. The item list in detail screens must match its visual and behavioral patterns exactly.

**Acceptance Scenarios**:

1. **Given** a user is viewing items in transaction detail, **When** they see the item list, **Then** items are rendered using `GroupedItemCard` (grouping by name/SKU/source, same logic as `SharedItemsList`), with each card showing a selector circle and status badge where applicable
2. **Given** a user taps the bulk select button when all items are already selected, **When** the toggle fires, **Then** all items are deselected (not re-selected)
3. **Given** a user has selected 3 items, **When** they look at the bottom of the screen, **Then** they see a sticky bottom bar showing "3 selected" and a "Bulk Actions" button
4. **Given** a user taps "Bulk Actions" in the bottom bar, **When** the bottom sheet opens, **Then** it shows context-appropriate actions (e.g., Set Space, Set Status, Set SKU, Remove, Delete for transaction detail; Move, Remove for space detail)
5. **Given** a user is viewing items in space detail, **When** they see the item list, **Then** it uses the same grouped card and bulk selection patterns as transaction detail and the project items tab

---

### User Story 2 - Item Detail Top Card and Sections (Priority: P1)

As a user viewing an item's detail screen, I see the item's description in the top card along with its linked transaction (showing source and amount as linked text) and its assigned space. Collapsible sections have no duplicate titles, no redundant "Move Item" section, and consistent spacing.

**Why this priority**: The item detail screen has the most individual issues (5 separate problems). Fixing them together as one story makes sense because they're all about the same screen and several are trivially small.

**Independent Test**: Navigate to an item that has a linked transaction and an assigned space. Verify the top card shows all three pieces of information, sections have single titles, and Move Item is in the kebab menu.

**Acceptance Scenarios**:

1. **Given** a user views an item with a linked transaction, **When** they see the top card, **Then** it shows: (a) the item description/name as the card title, (b) the linked transaction displayed as "Source - $Amount" (e.g., "Amazon - $149.99") as tappable linked text that navigates to the transaction detail screen, and (c) the assigned space name. The styling of the info row follows the same convention as the transaction detail hero card (label: value pairs separated by a pipe, using caption + body text variants).
2. **Given** a user views an item with no linked transaction, **When** they see the top card, **Then** the transaction info row is absent (not shown as "None" or "---")
3. **Given** a user views an item with no assigned space, **When** they see the top card, **Then** the space info is absent
4. **Given** a user expands the "Details" section, **When** they see the section content, **Then** there is ONE title (the collapsible section header "DETAILS") and the card content below has no redundant title
5. **Given** a user wants to move an item to a different transaction or space, **When** they open the kebab menu (more options), **Then** they see a "Move Item" action that opens the existing move form in a bottom sheet
6. **Given** a user views the item detail screen, **When** they look at the "Move Item" area that previously existed as an inline section, **Then** it is gone from the main screen body

---

### User Story 3 - Transaction Detail: Merge Tax into Details (Priority: P2)

As a user viewing a transaction's details, I see all detail information (source, date, amount, status, purchased by, reimbursement type, budget category, email receipt, subtotal, tax rate, tax amount) in a single "Details" collapsible section instead of two separate sections.

**Why this priority**: This is a simple structural change that reduces visual clutter. Lower priority because it doesn't break functionality; it's a UX improvement.

**Independent Test**: Open a transaction that has tax information. Verify there is one "DETAILS" section containing all detail rows including tax rows, not two separate sections.

**Acceptance Scenarios**:

1. **Given** a user is viewing a transaction with tax information, **When** they expand the "Details" section, **Then** they see all rows: Source, Date, Amount, Status, Purchased by, Reimbursement type, Budget category, Email receipt, Subtotal, Tax rate, Tax amount — in a single card
2. **Given** a user is viewing a transaction without tax information, **When** they expand the "Details" section, **Then** they see only the non-tax rows (the tax rows are omitted, not shown as empty)
3. **Given** a user is looking at the list of collapsible section headers, **When** they scan the screen, **Then** there is no "TAX & ITEMIZATION" section header — it has been merged into "DETAILS"

---

### User Story 4 - Consistent Section Spacing (Priority: P2)

As a user navigating between transaction detail, item detail, and space detail, the vertical spacing between collapsible sections feels consistent and compact. There is no noticeable difference in section gap between screens.

**Why this priority**: Inconsistent spacing is a polish issue that makes the app feel unfinished. It's a quick fix with high visual impact.

**Independent Test**: Open transaction detail, item detail, and space detail side by side (or in sequence). Verify the gap between collapsed section headers is identical across all three screens.

**Acceptance Scenarios**:

1. **Given** a user is on any detail screen, **When** they see collapsed sections stacked vertically, **Then** the gap between section headers is 4px (matching the tightest current implementation)
2. **Given** a user compares section spacing on transaction detail vs item detail vs space detail, **When** they look at the gaps, **Then** they are identical
3. **Given** a user views a screen with all sections collapsed, **When** they see the section list, **Then** the sections feel compact and visually grouped, not spaced out

---

### User Story 5 - Space Detail Default Sections (Priority: P3)

As a user opening a space detail screen, only the images section is expanded by default. Notes, items, and checklists are all collapsed.

**Why this priority**: Small behavioral fix. Currently items is also expanded by default, which pushes checklists below the fold unnecessarily.

**Independent Test**: Navigate to a space with images, items, and checklists. Verify only the images section is expanded on initial load.

**Acceptance Scenarios**:

1. **Given** a user navigates to a space detail screen, **When** the screen loads, **Then** the images section is expanded and notes, items, and checklists are collapsed
2. **Given** a user manually expands the items section, **When** they navigate away and come back, **Then** the default state applies again (images expanded, rest collapsed)

---

### Edge Cases

- What happens when a transaction has zero items? The item list section shows the empty state message; the bulk bar is not visible.
- What happens when all items in a group are identical but have different statuses? Each item card within the expanded group shows its own status badge.
- What happens when the user taps "Move Item" from the kebab menu on an item with no linked transaction? The move form still opens in a bottom sheet, showing only the space move option (no transaction move option).
- What happens when the linked transaction in the item detail top card has been deleted? The transaction info row should be absent (not a dead link). If the item's `transactionId` exists but the transaction data is not loadable, omit the transaction info.
- What happens when an item has no description/name? The top card shows "Untitled item" as the fallback title (matching existing behavior).
- What happens when a user has items selected and collapses the items section? The bulk bar at the bottom remains visible (selection is not cleared by collapsing). The user can still tap "Bulk Actions" to act on their selection.

## Requirements

### Functional Requirements

- **FR-001**: Item lists in transaction detail and space detail MUST use the `GroupedItemCard` component with the same grouping logic used in `SharedItemsList` (group key: `[name, sku, source].join('::').toLowerCase()`)
- **FR-002**: Item cards MUST display selector circles (via `onSelectedChange` prop) and status badges (via `statusLabel` prop) when those features are applicable in the current context
- **FR-003**: The bulk select toggle MUST deselect all items when all items are currently selected, and select all items when any items are unselected
- **FR-004**: Bulk selection controls MUST use a sticky bottom bar showing "{N} selected" and a "Bulk Actions" button. Tapping "Bulk Actions" opens a bottom sheet with context-appropriate actions. There MUST NOT be inline action buttons in the bulk bar itself.
- **FR-005**: The transaction detail "DETAILS" section MUST include tax/itemization rows (Subtotal, Tax rate, Tax amount) merged into the existing detail rows, eliminating the separate "TAX & ITEMIZATION" section. Tax rows are only shown when the transaction has tax data.
- **FR-006**: The item detail top card MUST display: (a) item name/description as the title, (b) linked transaction info shown as "Source - $Amount" tappable text that navigates to the transaction detail screen, and (c) the assigned space name. Transaction and space info are omitted (not shown as placeholders) when not present.
- **FR-007**: The item detail top card's transaction and space info MUST follow the same visual convention as the transaction detail hero card's info row: caption-variant labels, body-variant values, pipe separator between fields, baseline-aligned
- **FR-008**: All collapsible section content MUST NOT contain duplicate titles. If a `CollapsibleSectionHeader` provides the section title, the inner card/content MUST NOT render its own title
- **FR-009**: The "Move Item" functionality in item detail MUST be accessible from the kebab (more options) menu and MUST NOT appear as an inline section in the main screen body. When triggered, it opens the existing move form inside a bottom sheet.
- **FR-010**: The `contentContainerStyle.gap` value on every detail screen's SectionList MUST be 4px, producing consistent, compact spacing between collapsible sections
- **FR-011**: Space detail screens MUST default to only the images section expanded. Notes, items, and checklists MUST default to collapsed.
- **FR-012**: The `ItemsSection` component created in 004 MUST be retired and replaced with `SharedItemsList` (or a refactored version of it) that provides grouped cards, proper bulk UI, and all visual elements. The replacement MUST accept screen-specific bulk actions as configuration.
- **FR-013**: All changes MUST preserve existing offline-first patterns: no awaited Firestore writes in UI code, fire-and-forget with `.catch()`, cache-first reads in save handlers
- **FR-014**: All changes MUST preserve existing navigation, deep links, and screen transitions with no regressions

### Key Entities

- **GroupedItemCard**: A card component that groups visually similar items (by name/SKU/source) into a collapsible container. Shows a count badge, summary row when collapsed, and individual `ItemCard` instances when expanded. Already exists and is used in `SharedItemsList`.
- **SharedItemsList**: The existing item list component used in project and inventory tabs. Handles grouped rendering, bulk selection with bottom bar + bottom sheet, search/sort/filter. This is the reference implementation that detail screens should converge on.
- **ItemsSection**: The component created in 004 that should be retired. Uses plain `ItemCard`, has broken bulk UI, missing selector/status props.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Item lists in transaction detail and space detail visually match the existing item list in the project items tab and inventory items tab (grouped cards, selector circles, status badges, bottom bar bulk actions)
- **SC-002**: Bulk select toggle correctly deselects all items when all are selected, on every screen
- **SC-003**: Transaction detail has exactly one "DETAILS" collapsible section (no separate "TAX & ITEMIZATION" section)
- **SC-004**: Item detail top card shows linked transaction (as "Source - $Amount" linked text) and space when present, styled consistently with transaction detail hero card
- **SC-005**: Zero duplicate section titles exist on any detail screen (no case where a section header and inner card both display the same title)
- **SC-006**: Section spacing (gap between collapsible headers) is identical across transaction detail, item detail, and space detail (4px)
- **SC-007**: "Move Item" is accessible only through the kebab menu on item detail, not as an inline section
- **SC-008**: Space detail defaults to only images expanded on initial load
- **SC-009**: `ItemsSection` component is no longer imported or used anywhere in the codebase
- **SC-010**: All existing functionality is preserved: navigation, offline-first behavior, media upload, search/sort/filter, bulk operations
