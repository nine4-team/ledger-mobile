# Chat D: Transaction Items Control Bar with Full Feature Parity

## Goal

Implement a full-featured control bar for the Transaction Items section in `app/transactions/[id]/index.tsx` that matches the legacy web app's transaction detail items section.

Currently the transaction detail only has a single "Add Item" button. It needs search, sort, filter, bulk select, and full item context menus.

---

## Phase 1: Diagnostic - Legacy Web App (DO THIS FIRST)

Go to `/Users/benjaminmackenzie/Dev/ledger` and investigate the transaction detail page.

### Control Bar Analysis

- What controls exist in the items section control bar? (search, sort, filter, bulk select, add, etc.)
- What are the specific **SORT OPTIONS** available? (e.g., date created, alphabetical, price, etc.)
- What are the specific **FILTER OPTIONS** available? (e.g., by category, status, price range, etc.)
- Document any differences between these options vs the regular project items list

### Item Card Context Menu

- What menu options appear when you click the context menu (three dots/kebab) on an item card in the transaction items context?
- Document the full list of actions available
- Note any differences from item card menus in the regular project items list view

### Feature Differences

- Compare transaction items controls vs regular project items list controls
- What's added in transaction context?
- What's removed in transaction context?
- What's different (same feature but different options)?

### Bulk Operations

- What bulk actions are available when items are selected?
- How does bulk mode work in transaction context?

---

## Phase 2: Current Mobile App Review

### Examine existing control bar components

- `src/components/ListControlBar.tsx` - base component
- `src/components/ItemsListControlBar.tsx` - items-specific wrapper
- `app/project/[projectId]/spaces/[spaceId].tsx` - reference implementation

### Examine item card components

- `src/components/ItemCard.tsx` - what menu options does it support?
- How are context menus configured in different contexts?

### Identify reusable patterns

- What can be reused from existing components?
- What needs to be customized for transaction context?

---

## Phase 3: Implementation Plan

### Transaction-specific control bar

- Use shared `ListControlBar` component as base
- Configure with transaction-appropriate sort/filter/search options (from Phase 1)
- Always visible (not conditional on item count)
- Wire up all state management (search query, sort mode, filter mode, bulk selection)

### Configure item cards for transaction context

- Update `ItemCard` menu options to match transaction context (from Phase 1)
- Ensure bulk selection works correctly
- Hook up all menu action handlers

### Implement any missing features

- Add sort options that exist in legacy but not mobile
- Add filter options that exist in legacy but not mobile
- Implement any transaction-specific features identified

### Style consistency

- Match control bar styling from space detail screens
- Use theme-aware colors
- Ensure responsive layout

---

## Key Files

| File | Role |
|------|------|
| `app/transactions/[id]/index.tsx` | Main implementation target |
| `src/components/ListControlBar.tsx` | Shared base control bar |
| `src/components/ItemsListControlBar.tsx` | Items-specific control bar wrapper |
| `src/components/ItemCard.tsx` | Item card with context menu |
| `app/project/[projectId]/spaces/[spaceId].tsx` | Reference implementation |

---

## Critical Rules

1. **Actually inspect the legacy web app** - don't assume anything
2. **Document all differences** between transaction vs regular items context
3. **Include sort/filter OPTIONS**, not just that they exist
4. **Follow offline-first patterns** (no awaited Firestore writes)
5. **Use existing shared components** where possible
6. **Theme-aware** - use `useTheme()` / `useThemeContext()` tokens, never hardcode colors

## Deliverable

A detailed implementation plan documenting:

1. **Legacy feature audit** - exact controls, sort/filter options, context menu actions, and bulk operations from the web app's transaction items section
2. **Gap analysis** - what exists in mobile today vs what the legacy app provides, broken down by control bar features, item card menus, and bulk operations
3. **Implementation spec** - which shared components to reuse, what needs to be added/modified, state management approach, and file-by-file change list
4. **Open questions** - any design decisions or ambiguities that need resolution before coding begins
