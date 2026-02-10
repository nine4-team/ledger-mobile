# Feature Specification: Detail Screen Normalization

**Feature Branch**: `004-detail-screen-normalization`
**Created**: 2026-02-09
**Status**: Draft
**Input**: Extract shared patterns from the transaction detail SectionList refactor (Phases 1-2 complete) and apply them across all 4 detail screens. Normalize media handling, items management, collapsible sections, and detail row rendering into reusable components. Consolidate the two near-identical space detail screens. Target: reduce duplication and establish a consistent detail screen architecture.

## Context

The app has 4 detail screens that display a single entity's full information:

| Screen | File | Lines | Scroll |
|--------|------|-------|--------|
| Transaction detail | `app/transactions/[id]/index.tsx` | 1,622 | SectionList (refactored) |
| Item detail | `app/items/[id]/index.tsx` | 694 | AppScrollView |
| BI space detail | `app/business-inventory/spaces/[spaceId].tsx` | 1,042 | AppScrollView + StickyHeader |
| Project space detail | `app/project/[projectId]/spaces/[spaceId].tsx` | 1,050 | AppScrollView + StickyHeader |

Transaction detail was recently refactored to use SectionList with collapsible sections (Phases 1-2). The remaining screens still use AppScrollView with manual sticky headers or no sticky headers at all.

**Key problems today:**
- The two space detail screens are near-identical (~1,040 lines each) with only contextual differences (inventory vs project scope)
- Media handling uses two different patterns: `MediaGallerySection` (transactions, items) vs `ThumbnailGrid` + `ImageGallery` + `ImagePickerButton` (spaces)
- Items list + control bar + bulk operations logic is duplicated across 3 screens (transaction, both spaces)
- Detail row rendering (key-value pairs) is implemented inline in each screen with no shared component
- Only transaction detail has collapsible sections; other screens have no section collapse/expand affordance
- Sticky header implementation varies: native SectionList (transaction), StickyHeader component (spaces), none (items)

## Existing Shared Components

Components already shared across detail screens that this feature builds on (not creates from scratch):

| Component | Used By | Purpose |
|-----------|---------|---------|
| `Screen` | All 4 screens | Top-level chrome (header, back nav, menu) |
| `MediaGallerySection` | Transaction, item | Unified media gallery with add/remove/set-primary |
| `NotesSection` | All 4 screens | Expandable notes display |
| `ItemCard` | Transaction, both spaces | Item display with selection, menu, thumbnail |
| `ItemsListControlBar` | Transaction, both spaces | Search/sort/filter/add control bar |
| `SharedItemPicker` | Transaction, both spaces | Modal for adding existing items with tabs |
| `SpaceSelector` | Transaction, both spaces | Space picker with search and inline creation |
| `CollapsibleSectionHeader` | Transaction only | Collapsible section header (new from Phase 2) |
| `TitledCard` | Item, transaction sections | Card with section title header |
| `BottomSheet` / `BottomSheetMenuList` | All 4 screens | Modal menus and pickers |
| `SelectorCircle` | Transaction, ItemCard | Selection checkbox indicator |
| `StickyHeader` | Both spaces | Manual sticky wrapper (to be replaced) |

**Not shared yet (duplicated or screen-specific):**
- Bulk operations logic (state + handlers + modals) - duplicated in transaction + both spaces
- Space media uses `ThumbnailGrid` + `ImageGallery` + `ImagePickerButton` directly instead of `MediaGallerySection`
- Detail rows (key-value pairs) - inline in each screen, no shared component
- Items management orchestration (selection state, sort/filter state, handlers) - duplicated

**Shared hooks:**
- `useOutsideItems` - used by transaction + both spaces for "Outside" tab in item pickers

## User Scenarios & Testing

### User Story 1 - Consistent Collapsible Sections Across All Detail Screens (Priority: P1)

As a user viewing any detail screen (transaction, item, or space), I can collapse and expand sections to focus on the information I care about. The interaction feels the same everywhere: same chevron icon, same touch target, same visual treatment.

**Why this priority**: Collapsible sections are the architectural foundation that all other extraction work builds on. The SectionList + CollapsibleSectionHeader pattern proven in transaction detail must be applied to the other screens first, establishing the shared section rendering architecture.

**Independent Test**: Navigate to item detail and space detail screens. Verify that sections can be collapsed/expanded using the same CollapsibleSectionHeader component already working on transaction detail.

**Acceptance Scenarios**:

1. **Given** a user is viewing item detail, **When** they tap a section header (e.g., Notes, Details), **Then** the section collapses/expands with the same chevron affordance as transaction detail
2. **Given** a user is viewing a space detail screen, **When** they tap a section header, **Then** the section collapses/expands identically to transaction detail
3. **Given** a user is on any detail screen, **When** they see a collapsible section header, **Then** it has the same visual treatment: uppercase title, chevron icon, optional badge, 44pt minimum touch target

---

### User Story 2 - Unified Space Detail Screen (Priority: P1)

As a user managing spaces, whether in business inventory or within a project, I get the same experience. The two near-identical space detail screens are consolidated into a single component that adapts to its context.

**Why this priority**: The two space screens share ~95% of their code. Consolidating them eliminates the largest source of duplication in the codebase and prevents future drift. This is a high-value, low-risk change.

**Independent Test**: Navigate to a space from business inventory and from a project. Verify both render identically using the same underlying component, with only contextual differences (navigation targets, scope).

**Acceptance Scenarios**:

1. **Given** a user navigates to a space from business inventory, **When** the space detail loads, **Then** it shows the same sections and functionality as before (images, notes, items, checklists)
2. **Given** a user navigates to a space from a project, **When** the space detail loads, **Then** it shows the same sections and functionality, with project-specific context (e.g., project items in picker)
3. **Given** a developer modifies the space detail screen, **When** they make a change, **Then** only one file needs updating (not two nearly-identical files)

---

### User Story 3 - Shared Items Management (Priority: P2)

As a user managing items on any screen that has an items list (transaction detail, space detail), I get a consistent experience: the same control bar, the same search/sort/filter, the same bulk selection, the same bulk actions.

**Why this priority**: Items management (control bar + search + sort + filter + bulk operations) is the single largest block of duplicated logic, appearing in transaction detail and both space detail screens. Extracting it into shared components delivers the biggest LOC reduction and ensures consistent item management behavior.

**Independent Test**: On transaction detail and space detail, verify that items search, sort, filter, and bulk operations all work identically using shared components.

**Acceptance Scenarios**:

1. **Given** a user is on transaction detail with items expanded, **When** they search, sort, or filter items, **Then** the behavior is identical to the same actions on space detail
2. **Given** a user selects multiple items on any screen, **When** they open the bulk actions menu, **Then** available actions are consistent (with screen-specific additions where appropriate)
3. **Given** a user is on space detail, **When** the items section control bar becomes sticky, **Then** it uses native SectionList sticky headers (not the manual StickyHeader component)

---

### User Story 4 - Normalized Media Handling (Priority: P2)

As a user adding or viewing media (images, receipts, PDFs) on any detail screen, the experience is consistent. All screens use the same media component regardless of whether the entity is a transaction, item, or space.

**Why this priority**: Media handling currently uses two different component patterns. Normalizing to a single approach (MediaGallerySection) simplifies development, ensures consistent UX, and enables shared upload/delete/reorder logic.

**Independent Test**: On space detail screens, verify media gallery uses the same `MediaGallerySection` component pattern as transaction and item detail, with the same add/remove/set-primary interactions.

**Acceptance Scenarios**:

1. **Given** a user is viewing a space, **When** they see the images section, **Then** it uses `MediaGallerySection` (or an equivalent shared component) rather than a bespoke ThumbnailGrid arrangement
2. **Given** a user adds an image on any detail screen, **When** the upload completes, **Then** the interaction pattern is the same: pick, save locally, fire-and-forget upload
3. **Given** a user sets a primary image on any detail screen, **When** they tap the primary action, **Then** the affordance and behavior are identical

---

### User Story 5 - Shared Detail Rows Component (Priority: P3)

As a user viewing entity details (date, amount, category, vendor, SKU, etc.), the key-value row presentation is visually consistent across all detail screens. Labels, values, dividers, and tap-to-copy behavior all follow the same pattern.

**Why this priority**: Detail rows are rendered inline in each screen today. While less code than items management, standardizing them ensures visual consistency and reduces per-screen boilerplate. Lower priority because each screen's detail rows have different fields, so the shared component is about presentation, not business logic.

**Independent Test**: Compare detail rows on transaction detail, item detail, and space detail. Verify they use a shared `DetailRow` (or similar) component with consistent styling.

**Acceptance Scenarios**:

1. **Given** a user views transaction details, **When** they see key-value rows (source, date, amount, category), **Then** each row uses a shared detail row component
2. **Given** a user views item details, **When** they see key-value rows (SKU, price, space), **Then** the same shared component is used with the same visual treatment
3. **Given** a developer adds a new detail field to any screen, **When** they use the shared component, **Then** it automatically follows the established row styling (label left, value right, divider below)

---

### Edge Cases

- What happens when a section has no content (e.g., no notes, no media)? Hidden entirely on all screens.
- How does the consolidated space screen handle features that only exist in one context (e.g., project-only actions)? Context-specific features are conditionally rendered based on scope prop.
- What happens to existing deep links and navigation when space screens are consolidated? Route structure is preserved; the shared component is rendered by both route files (thin wrappers).
- How do screens behave offline? All existing offline-first patterns are preserved: fire-and-forget writes, cache-first reads, no spinners blocking on server acknowledgment.

## Requirements

### Functional Requirements

- **FR-001**: All detail screens (transaction, item, space) MUST use `SectionList` as their scroll container with `stickySectionHeadersEnabled` for items sections
- **FR-002**: All collapsible section headers MUST use the shared `CollapsibleSectionHeader` component with consistent chevron icons, 44pt touch target, uppercase title, and optional badge
- **FR-003**: The two space detail screens MUST share a single `SpaceDetailContent` component (or equivalent), with route-level wrappers providing scope context
- **FR-004**: Items management (control bar, search, sort, filter, bulk selection, bulk actions) MUST be extracted into shared components usable by any screen with an items list
- **FR-005**: Media handling MUST be normalized so all detail screens use a consistent media component pattern (converging on `MediaGallerySection` or an evolution of it)
- **FR-006**: Detail row rendering (key-value pairs) MUST use a shared component for consistent visual treatment across all screens
- **FR-007**: All existing functionality on every detail screen MUST be preserved with no regressions (navigation, offline-first behavior, deep links, media upload, item management)
- **FR-008**: Section default collapsed/expanded state MUST be configurable per screen (e.g., transaction detail defaults differ from item detail defaults)
- **FR-009**: Extracted components MUST follow existing offline-first coding rules: no awaited Firestore writes in UI, fire-and-forget with `.catch()`, cache-first reads in save handlers
- **FR-010**: The manual sticky header implementations (StickyHeader component wrapping control bars) in space detail screens MUST be replaced by native SectionList sticky headers

### Key Entities

- **Detail Screen**: A screen displaying a single entity's full information, composed of collapsible sections rendered in a SectionList
- **Section**: A collapsible content group within a detail screen (e.g., Media, Notes, Details, Items, Audit) with a header, optional badge, and expand/collapse state
- **Items Manager**: The shared items list experience: control bar with search/sort/filter, item cards, bulk selection, bulk action modals
- **Detail Row**: A single key-value display pair within a Details section, with label, value, optional tap action, and divider

## Success Criteria

### Measurable Outcomes

- **SC-001**: Space detail duplication is eliminated: one shared component replaces two near-identical ~1,040-line files
- **SC-002**: Total lines of code across all 4 detail screens is reduced by at least 30% from current combined total (~4,408 lines)
- **SC-003**: All detail screens use the same collapsible section pattern, verifiable by visual inspection (consistent chevrons, touch targets, animation)
- **SC-004**: Items management code exists in one place: changes to search, sort, filter, or bulk operations require editing only the shared component, not multiple screens
- **SC-005**: A developer can add a new detail screen (e.g., for a future entity) by composing existing shared components (SectionList, CollapsibleSectionHeader, items manager, media section, detail rows) without duplicating logic
- **SC-006**: All existing manual test scenarios for each detail screen continue to pass after normalization (no functional regressions)
- **SC-007**: Offline-first behavior is preserved: all Firestore writes remain fire-and-forget, no new loading spinners that block on server acknowledgment
