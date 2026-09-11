# Search Results & Item Detail — Contextual Details
Status: shipped
Last updated: 2026-04-10

> **Target boundary:** Preserve the shipped search controls and matching
> capabilities below, with canonical Item identity, Client ownership and
> authorized local readiness. The old scope-derived purchaser fallback is not
> payment evidence. Target search has real Items, Transactions and Spaces, not
> recurring ProtoItem results. Imported legacy capture evidence follows its
> migration workflow. No Firebase implementation is required.

## Target Search Contract

Preserve the first-class Search page, focused text input, debounce and Clear;
Items/Transactions/Spaces segments with visible counts; and automatic selection
of the sole other nonempty segment when the current segment has no matches.
Query clearing returns the initial prompt, not an unfiltered full directory.
Refresh results when relevant local values change, not only when array counts
change. Known-empty, query-no-match, incomplete/stale and failed data remain
distinct; hidden rows, names, counts and financial amounts never enter the
authorized search projection (O-060).

Preserve the discovered matching capabilities from `SearchCalculations.swift`:

- Item text: stable ID, display name, original/current source, raw SKU, notes
  and eligible category name; also normalized SKU matching after removing
  non-alphanumeric characters and lowercasing.
- Item amounts: acquisition/project/market amounts; Transaction amounts:
  actual amount. Preserve dollar-prefix matching with dollar signs/commas
  ignored and magnitude matching for negative amounts. Use exact integer-Money
  formatting rather than making floating-point precision part of the contract.
- Transaction text: ID, canonical display name/type, notes, authoritative payer
  evidence where known, and eligible category label. Never index retired
  `paymentToBusiness` as a new target type or infer payer from placement alone.
- Space text: ID, name and notes. Text matching remains case-insensitive
  substring matching; preserve tested source cases, including punctuation and
  SKU/amount examples. O-055 still governs unresolved portable Space matching;
  do not silently replace the existing broader search with name-only matching.

Open results by exact stable identity into current detail or an explicit
entity-specific unavailable state. Item rows show Project/Inventory context;
detail shows canonical Client/Project, Space, current accounting links and
visibility-safe history. One current placement does not erase prior cycles.
Unknown payer/relationships remain unknown, not scope-derived guesses.

Preserve Item/Transaction selection, mutually exclusive selection modes,
segment-change clearing, selected counts/eligible totals, Copy ID(s) and Clear.
Status, Link/clear-accounting, Space assignment/clear, correction/movement and
deletion controls invoke their owning approved workflows with fresh selection
and authorization. Search is not a second writer, generic reassignment command
or bypass of paid/deletion/rejection rules. Its full action parity is blocked
where those owning workflows remain unresolved.

Route acceptance tests must cite the owning workflow's verified behavior and
exercise selected identities, cancellation and unavailable/denied destinations;
they do not require Search-specific database commands. O-029 covers Transaction
deletion only. Item deletion remains an explicit unresolved lifecycle/retention
decision (O-064), not an implicitly approved action or a silently retired feature.
Accounting history in detail composes O-015 provenance and O-060 visibility.

## Shipped Source Evidence

The remaining historical sections describe the shipped context enhancement,
not target payer inference. Preserve Client/Business labels only when supported
by canonical evidence; the source placement fallback is explicitly excluded.
The target applies on iOS and macOS; old discovery questions do not reopen that
platform scope.

> **Shipped 2026-04-10** — Search result rows display the project name (UniversalSearchView.swift line 278 passes `projectName(for: item.projectId)` into ItemCard, rendered at ItemCardCalculations.swift lines 59-61 as "Project: {name}"). Item detail hero card now shows Project, Purchaser, Budget Category, Transaction, and Space. The Purchaser row (ItemDetailView.swift `purchaserLabel`) reads `item.purchasedBy` if set and normalizes to "Client" or "Business"; when unset it falls back to scope (no project → Business, has project → Client).

## Summary
When searching for items across the app, the user needs enough context to identify which item they're looking at — specifically, which project it belongs to. The full mapping details (location, transaction, purchaser, etc.) should be accessible when the user clicks into the item detail view, not necessarily crammed into the search result row itself.

## Scope
- Applies to the **designated search page** and **item detail view** across the app
- Applies to **all supported platforms**.

## How It Should Work

### Search Result Row
Each search result should show enough context to differentiate items at a glance. The key addition is the **project name** — so the user can tell which client's project the item belongs to.

- **Item name and basic info**: [exact fields currently shown TBD via discovery]
- **Project name**: Which project the item is in (e.g., "Smith Residence"). This is the critical missing piece — especially when "purchased by client," the user needs to see *which* client's project to know who.
- **Purchaser label**: Can remain as "Client" or "Business" — no need to show the specific client's name as long as the project name is visible

The search result row does **not** need to show every detail. It just needs enough for the user to say "that's the one" and click in.

### Item Detail View (click into an item)
When the user taps/clicks on an item from search results (or anywhere in the app), the item detail view should show the full mapping and context:

- **Project**: Which project the item belongs to
- **Space**: Which space the item is in (if applicable)
- **Inventory/Account**: Which inventory or account it's associated with
- **Transaction**: Which transaction the item is tied to (reference/number, date, or identifier)
- **Purchaser**: "Client" or "Business"
- **Any other location/relationship details** that help the user understand where this item sits in the system

The goal: the user should be able to open any item and see the complete picture of where it lives and what it's connected to, all in one place.

## What's Changing

### Staying the Same
- The search input and query behavior
- The purchaser label format ("Client" or "Business" is fine as-is)
- The existence of the search page and item detail view

### Changing
- **Search result rows**: Add the project name so the user can see which client's project an item belongs to
- **Item detail view**: Ensure all mapping/location details are present and visible (project, space, inventory, transaction, purchaser)

### Adding
- **Project name on search results**: visible in the result row
- **Full mapping section on item detail**: all location and relationship info consolidated in one view

### Removing
- Nothing removed

## Open Questions

Source discovery above and the exact-control checklist resolve the old questions
about result fields and entity types. Canonical specs resolve one Item/current
placement with historical provenance. Remaining gates are owning action rules,
financial visibility and O-055 matching—not whether Transactions are searchable.
