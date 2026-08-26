# Item Filtering

## Purpose
Provides transaction-style grouped filtering for shared project, inventory, space, transaction-detail, and picker item lists.

## Files

- `LedgeriOS/LedgeriOS/Models/Shared/ItemListEnums.swift` — owns `ItemFilterState`, facet selection semantics, and canonical filter values.
- `LedgeriOS/LedgeriOS/Logic/ListFilterSortCalculations.swift` — applies pure grouped predicates before search and sort.
- `LedgeriOS/LedgeriOS/Components/FilterMenu.swift` — builds the scope-aware grouped item filter sheet.
- `LedgeriOS/LedgeriOS/Components/SharedItemsList.swift` — derives dynamic options, owns active state, and applies selection safety.
- `LedgeriOS/LedgeriOS/Components/ActionMenuSheet.swift` — renders facet summaries and uses explicit active-filter metadata for Clear visibility.

## State

`SharedItemsList` owns an `ItemFilterState`. Each `ItemFacetSelection` is one of:

- `all` — every current and future value is included.
- `only(Set<String>)` — only named values are included; an empty set represents None.
- `allExcept(Set<String>)` — every value except the named exclusions is included.

Values within a facet are ORed. Facets are ANDed. The state is local to the list and is not persisted between screens or launches.

## Data

Filtering is entirely client-side over the items already loaded by the owning context. It performs no additional Firestore reads or writes.

- Source uses `item.currentSource ?? item.source`, trimmed and matched case-insensitively.
- Space and budget-category filters use exact document IDs.
- Missing nil, empty, and whitespace-only strings map to the shared `__missing__` sentinel.
- Purchased By maps known legacy spellings containing client/design/business into the canonical options.

`SharedItemsList` accepts spaces and budget categories from its owning context. Archived spaces are omitted unless a current item references them. Referenced IDs missing from the provided lookup remain filterable as Unknown Space or Unknown Category.

## Sheets & Navigation

The existing Filter toolbar button presents `ItemFilterMenu` through `adaptivePresentation(style: .selectionMenu)`. Submenu selections do not close the sheet. Clear resets every visible facet to All. The Space facet is hidden on Space Detail because that list is already space-scoped; Budget Category is hidden for inventory because inventory items cannot have categories.

## Gotchas

- All and None are state-changing controls, not stored item values.
- Selecting every currently available value normalizes back to All so newly arriving values are included.
- Item quick drafts are hidden whenever persisted-item facets are active; proto-item fields/statuses are not equivalent to Item fields/statuses.
- Changing filters intersects bulk-selected IDs with visible item IDs to prevent hidden bulk mutations.
- The legacy flat `ItemFilterOption` calculations remain for compatibility tests and callers, but `SharedItemsList` uses only the grouped filter pipeline.
