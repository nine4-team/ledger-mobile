# Implementation Plan: Detail Screen Polish

**Branch**: `005-detail-screen-polish` | **Date**: 2026-02-10 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/kitty-specs/005-detail-screen-polish/spec.md`

## Summary

Fix 8 regressions and omissions from feature 004-detail-screen-normalization across transaction detail, item detail, and space detail screens. The primary fixes are:

1. **Replace ItemsSection with SharedItemsList pattern** - Detail screens will use grouped item cards (`GroupedItemCard`), proper bulk selection UI (sticky bottom bar + bottom sheet), and full visual parity with the project/inventory item tabs
2. **Fix item detail top card** - Display linked transaction as "Source - $Amount" navigable text, show assigned space, fix info row styling
3. **Merge tax into details section** - Combine Tax/Itemization and Details into single collapsible section in transaction detail
4. **Remove duplicate section titles** - Fix CollapsibleSectionHeader + inner Card double-title bug
5. **Normalize section spacing** - Use consistent 4px gap between collapsible sections across all detail screens
6. **Move "Move Item" to kebab menu** - Remove inline section, add menu action that opens bottom sheet
7. **Fix bulk selection toggle** - Deselect all when all items already selected
8. **Fix space detail defaults** - Only images section expanded by default

**Technical Approach**: Refactor `SharedItemsList` to be configurable for embedding in detail screen sections. Extract shared bulk action logic and grouped item rendering into reusable components that both the standalone list and section fragment can use.

## Technical Context

**Language/Version**: TypeScript 5.3.3, React Native 0.76.9, Expo SDK 52
**Primary Dependencies**:
- React Native Firebase (Firestore, Storage, Auth)
- Expo Router 4.0 (file-based routing)
- Zustand 5.0 (state management)
- @nine4/ui-kit 0.2.1 (design system)

**Storage**:
- Firestore (offline-first with cache, no awaited writes in UI)
- expo-sqlite (local media tracking)
- Firebase Storage (media uploads)

**Testing**: Manual visual QA against acceptance scenarios, before/after screenshots

**Target Platform**: iOS 15+ and Android (React Native mobile app)

**Project Type**: Mobile application (Expo/React Native)

**Performance Goals**:
- 60 fps scrolling in item lists
- Instant UI feedback on selection/bulk actions (offline-first)
- <100ms response to user interactions

**Constraints**:
- Offline-first architecture - no `await` on Firestore writes in UI code
- Fire-and-forget writes with `.catch()` error logging
- Cache-first reads in save handlers (`mode: 'offline'`)
- Preserve existing navigation patterns and deep links
- No visual regressions in other screens

**Scale/Scope**:
- 3 detail screens (transaction, item, space)
- 5 user stories (3 P1, 2 P2)
- 1 component retirement (ItemsSection)
- 14 functional requirements

## Constitution Check

*No constitution file exists at `.kittify/memory/constitution.md` - skipping constitution check.*

## Planning Decisions

### Component Refactoring Strategy

**Decision**: Refactor `SharedItemsList` to be configurable for reuse in detail screens (Option A)

**Rationale**:
- Maintains single source of truth for item list behavior
- Ensures visual consistency across all screens
- Future improvements benefit all use cases
- Avoids code duplication and drift

**Implementation approach**:
- Extract core rendering logic (grouped cards, bulk UI) into composable pieces
- Add props to configure context-specific bulk actions
- Support both standalone (full-page) and embedded (section) modes
- Detail screens will import and configure SharedItemsList for their specific context

### Section Spacing Strategy

**Decision**: Wrap header + content in a single View per section (Option A)

**Problem Identified**: The `gap` property on `SectionList` `contentContainerStyle` applies to all direct children, meaning it controls both section-to-section spacing AND header-to-content spacing. Setting `gap: 4` would make header-to-content spacing too tight.

**Solution**: Wrap each section's `CollapsibleSectionHeader` + `Card` content in a View with `gap: 12` (internal), then set `contentContainerStyle.gap: 4` for section-to-section spacing.

**Rationale**:
- Minimal changes to existing JSX structure
- Semantically correct (section as single entity)
- No component pollution (doesn't add margins to Card/CollapsibleSectionHeader)
- Works with existing collapse logic (content still unmounts when collapsed)
- Keeps Card component clean for use in other contexts

**Implementation**: See quickstart.md §2 for code pattern

### Work Package Structure

**Decision**: Single integrated work package covering all 5 user stories (Option A)

**Rationale**:
- Fixes are tightly coupled (same screens, same components, shared patterns)
- Artificial splits would create coordination overhead and merge complexity
- Section spacing normalization affects all screens simultaneously
- Testing happens once at the end with complete context

**Work Package Breakdown**:
- **WP01**: Complete detail screen polish pass
  - Replace ItemsSection usage with SharedItemsList pattern
  - Fix item detail top card and sections
  - Merge tax into details in transaction detail
  - Normalize section spacing to 4px
  - Fix bulk toggle logic and default expanded states

### Testing Approach

**Decision**: Manual visual QA with before/after screenshots (Option A)

**Rationale**:
- Appropriate scope for UI polish work
- Acceptance criteria are visually specific (grouped cards, spacing, badges)
- Use project items tab as visual reference
- Fast iteration without test maintenance overhead

**Test Strategy**:
- Capture before screenshots of all three detail screens
- Manual verification against each acceptance scenario in spec
- Visual comparison with project items tab (reference implementation)
- Edge case verification (empty lists, deleted transactions, no descriptions)
- Verify offline-first patterns preserved (no UI blocking on server)

### Edge Case Handling

**Clarified from planning**:
- **Deleted/unavailable linked transactions**: Display "Transaction: [Deleted]" or "Transaction: Unavailable" in item detail top card (do NOT hide the row)
- Empty item lists: Show empty state message, hide bulk bar
- Items with no description: Show "Untitled item" as fallback title
- Selection state: Persists when sections are collapsed (bulk bar remains visible)

## Project Structure

### Documentation (this feature)

```
kitty-specs/005-detail-screen-polish/
├── plan.md              # This file (/spec-kitty.plan output)
├── research.md          # Phase 0: Component analysis and refactoring patterns
├── quickstart.md        # Phase 1: Developer guide for detail screen patterns
└── tasks.md             # Phase 2: NOT created by /spec-kitty.plan - generated by /spec-kitty.tasks
```

### Source Code (repository root)

```
src/
├── components/
│   ├── SharedItemsList.tsx           # [MODIFY] Refactor for configurability
│   ├── ItemsSection.tsx              # [RETIRE] Replace usage with SharedItemsList
│   ├── GroupedItemCard.tsx           # [REFERENCE] Already implements grouping pattern
│   ├── ItemCard.tsx                  # [REFERENCE] Base card component
│   ├── CollapsibleSectionHeader.tsx  # [REFERENCE] Section headers
│   ├── Card.tsx                      # [MODIFY] Fix double-title bug if present
│   ├── TitledCard.tsx                # [REVIEW] May need title suppression prop
│   └── DetailRow.tsx                 # [REFERENCE] Info row styling for item detail
│
├── screens/              # [Legacy location, unused by Expo Router]
│
└── hooks/
    └── useItemsManager.ts            # [REVIEW] State management for item lists

app/
├── transactions/[id]/
│   ├── index.tsx                     # [MODIFY] Transaction detail screen
│   └── sections/                     # [MODIFY] Tax/Details section merge
│
├── items/[id]/
│   ├── index.tsx                     # [MODIFY] Item detail screen
│   └── edit.tsx                      # [REVIEW] May need updates for consistency
│
└── project/[projectId]/spaces/
    └── [spaceId].tsx                 # [MODIFY] Space detail screen (or SpaceDetailContent.tsx)
```

**Structure Decision**: This is a mobile application using Expo Router's file-based routing. Screens live in `app/` directory with dynamic routes via `[param]` syntax. Shared components live in `src/components/`. The feature will primarily modify detail screen implementations and refactor the SharedItemsList component to support both standalone and embedded usage patterns.

## Complexity Tracking

*No constitution file exists, so no violations to track. Standard React Native component refactoring with attention to offline-first patterns and visual consistency.*

## Phase 0: Research

**Status**: ✅ Complete

**Research Questions Addressed**:
1. How does SharedItemsList currently handle grouped items and bulk actions?
2. What are the key differences between ItemsSection and SharedItemsList?
3. What are the current section spacing values across detail screens?
4. How does item detail currently display linked transaction info?

**Findings**: See [research.md](research.md) for complete analysis.

**Key Insights**:
- SharedItemsList uses GroupedItemCard with grouping key: `[name, sku, source].join('::').toLowerCase()`
- ItemsSection is a lightweight section fragment (not standalone) - lacks grouping, has broken bulk UI
- Current spacing inconsistent: transaction (gap: 10), item (gap: 18), space (gap: 20)
- Item detail shows transaction as truncated ID link - needs "Source - $Amount" format
- Bulk selection bottom bar pattern: sticky bar with "{N} selected" + "Bulk Actions" button → bottom sheet

## Phase 1: Design & Contracts

**Status**: ✅ Complete

### Data Model

**No new entities**. This is a UI polish feature that works with existing data models:
- `ScopedItem` (existing)
- `Transaction` (existing)
- `Space` (existing)

**No data model changes required**. All fixes are presentation-layer only.

### API Contracts

**No API changes**. This feature modifies only the UI layer:
- No new Firestore queries
- No new Firebase Functions
- No new REST endpoints
- All data access uses existing service functions

### Component Contracts

**Modified Components**:

1. **SharedItemsList.tsx**
   - Add `embedded` mode prop (boolean) - when true, renders without top control bar
   - Add `bulkActionsConfig` prop - allows parent to specify context-specific actions
   - Extract `useGroupedItems` hook for sharing grouping logic
   - Extract `BulkSelectionBar` as separate component
   - Maintain existing API for standalone usage (backward compatible)

2. **ItemsSection.tsx**
   - Mark as deprecated
   - Usage replaced by SharedItemsList in embedded mode
   - Can be removed in future cleanup (not in this feature)

3. **Item Detail Hero Card** (app/items/[id]/index.tsx)
   - Update transaction display from ID to "Source - $Amount"
   - Add space info row when item has assigned space
   - Style info rows with caption/body variants, pipe separator, baseline alignment
   - Handle edge case: deleted transaction → "Transaction: [Deleted]"

4. **Transaction Detail** (app/transactions/[id]/index.tsx)
   - Merge tax/itemization rows into Details section
   - Remove separate "TAX & ITEMIZATION" section header
   - Update section gap from 10 to 4
   - Wrap header + content in View with `gap: 12` for internal spacing
   - Replace ItemsSection usage with SharedItemsList (embedded mode)

5. **Item Detail** (app/items/[id]/index.tsx)
   - Update section gap from 18 to 4
   - Wrap header + content in View with `gap: 12` for internal spacing

6. **Space Detail** (SpaceDetailContent.tsx or app/project/[projectId]/spaces/[spaceId].tsx)
   - Update default expanded sections (only images expanded)
   - Update section gap from 20 to 4
   - Wrap header + content in View with `gap: 12` for internal spacing
   - Replace ItemsSection usage with SharedItemsList (embedded mode)

### Developer Quickstart

See [quickstart.md](quickstart.md) for:
- How to use SharedItemsList in embedded mode
- Detail screen section patterns
- Consistent spacing guidelines
- Theme usage for info rows
- Offline-first checklist

## Phase 2: Task Generation

**NOT INCLUDED IN THIS COMMAND**. The user must run `/spec-kitty.tasks` to generate work packages.

## Success Criteria

All success criteria from spec.md must be met:

- ✅ SC-001: Item lists in detail screens visually match project items tab
- ✅ SC-002: Bulk select toggle correctly deselects when all selected
- ✅ SC-003: Transaction detail has single "DETAILS" section (tax merged)
- ✅ SC-004: Item detail top card shows linked transaction as "Source - $Amount" with proper styling
- ✅ SC-005: Zero duplicate section titles across all screens
- ✅ SC-006: Consistent 4px section spacing across all detail screens
- ✅ SC-007: "Move Item" only in kebab menu, not inline section
- ✅ SC-008: Space detail defaults to only images expanded
- ✅ SC-009: ItemsSection no longer imported or used
- ✅ SC-010: All existing functionality preserved (navigation, offline-first, media, bulk ops)

## Next Steps

1. **User**: Review this plan and confirm alignment
2. **User**: Run `/spec-kitty.tasks` to generate work packages and implementation prompts
3. **User**: Run `/spec-kitty.implement <WP-id>` to create worktree and begin implementation
