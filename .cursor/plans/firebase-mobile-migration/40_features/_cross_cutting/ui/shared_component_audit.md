# Shared UI component audit (Spaces + Transactions add-item flows)

This note captures where we failed to use existing shared UI components and what shared components are still missing.

## Shared components we already have (and should use)

- `ItemCard` in `src/components/ItemCard.tsx` (previously `ItemPreviewCard.tsx`).
- `GroupedItemCard` in `src/components/GroupedItemCard.tsx` (previously `GroupedItemListCard.tsx`).
- `SegmentedControl` in `src/components/SegmentedControl.tsx`.

## Fixed: add-existing pickers now use shared components

- `app/transactions/[id].tsx`: add-existing picker now uses `SegmentedControl` + `ItemCard`/`GroupedItemCard`.
- `app/project/[projectId]/spaces/[spaceId].tsx`: add-existing picker now uses `SegmentedControl` + `ItemCard`/`GroupedItemCard`.

## Shared components now implemented

- Shared add-existing-items picker UI (tabs, search, select-all, duplicate grouping, sticky add button).
- Shared “outside items” fetch + filter hook (other projects + optional inventory).
- Shared conflict dialog (“Reassign items?”).
- Shared pull-in / re-home helper (move/allocate rules before linking or space assignment).

## Suggested refactor targets

- `SharedItemPicker` (UI + group logic)
- `useOutsideItems` (data)
- `resolveItemMove` (pull-in / re-home behavior)
