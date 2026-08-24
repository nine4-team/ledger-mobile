# Hal Roe Missing Budget Category Audit

Generated from production Firestore (`ledger-nine4`) on 2026-08-24. The initial audit was read-only. The reviewed 47-item repair was then applied and independently verified in production.

## Scope

- Account: `1584 Design` (`1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`)
- Project: `Hal Roe — Trinidad Vacation Rental` (`pgwdhOFcslItEjDxeWgL`)
- Current project items scanned: 635
- Items matched by the app's `Uncategorized` filter before repair: 47
- Items matched by the app's `Uncategorized` filter after repair: 0

The app's filter matches items whose `budgetCategoryId` is absent/null or trims to an empty string. In this project all 47 matches are absent/null; there are no whitespace-only values.

## Finding

All 47 items are canonically attached to one of five Purchase transactions. Every one of those transactions has the valid, project-enabled `Furnishings` category (`da556858-1df8-40be-b10c-b15710d7cc9a`). There are no missing transactions, stale transaction back-references, unknown category IDs, `uncategorized` sentinel values, or categories disabled for this project among these items.

The linked transaction therefore provided an unambiguous expected category for every item: `Furnishings`.

The common cause is the MCP `bulk_create_items` path. Unlike `create_item`, it does not inherit `budgetCategoryId` from the linked transaction when callers omit the per-item value. The transaction audit notes and identical item creation timestamps show these records were created in bulk during transaction itemization work.

## Items

### Homegoods — transaction `0tha40ZlO2viSnxGPVO6` (26 items)

| Item ID | Item | SKU |
|---|---|---|
| `FMNtveOXfQGUDSUjpyom` | Black Agate Decor | `409065` |
| `q4clAsIKfqG7j3sDEVU9` | Black Handmade Terra Cotta Bowl | `368608` |
| `5XnQHu3L7vrgKAb8LbcH` | Blue Herringbone Italian Throw | `146986` |
| `H5FD89XHA7rrDmgymrPK` | Blue Herringbone Italian Throw | `146986` |
| `CeG5JSYMvcIdhCyiRWwT` | Blue Herringbone Throw | `146986` |
| `SwKOJtcKbWSEZBjnLCBF` | Coasters | `001876` |
| `LfUjZqjXuNRSR2sGKcpO` | Everyday Q-Line Item | `120206` |
| `cQpzHcMnsZaSExIRmuLF` | Everyday Q-Line Item | `120206` |
| `gHgFewmdTaYcwLoPcvy6` | Everyday Q-Line Item | `120206` |
| `iCgUKH914FOdxvqUYiKh` | Gray Pot with Succulents | `925642` |
| `mCJgWkk1Q5EMZqWH7AZk` | Green Lumbar Pillow | `080549` |
| `zEW3tXS6lriNZ5QkOMhc` | King Comforter | `244337` |
| `8XvyUy535A0t2t7IFOfC` | Large Square Yellow Chenille Pillow | `080427` |
| `IRgU3iJVNJ0a91o6A394` | Large Square Yellow Chenille Pillow | `080427` |
| `JQNx9SOG42Mksbeu9FCM` | Large Square Yellow Chenille Pillow | `080427` |
| `1NfL08yX8s6Jvd9MfwbP` | Light Blue Pillow | `076187` |
| `2yyayVPvlQfihQxonJb4` | Light Blue Square Pillow with Tassel | `076187` |
| `NiqOlBXxfqwb1qwyxL6v` | Light Orange Long Lumbar Pillow | `080545` |
| `9hoifBxOyZ937MSghvDr` | Long Green Chenille Lumbar Pillow | `080549` |
| `B6GaLr2VQxohQMNU2zmJ` | Navy Throw | `146413` |
| `nlsNdWJfspQp0o0TQgOr` | Rectangle Bamboo Cutting Board with Faux-Leather Handle | `463130` |
| `P0SG4s1KWCHHy2CtdiWc` | Set of 2 Blue Velvet Lumbar Pillows | `071959` |
| `GSomdKJvZm9x28h39Br3` | Set of 4 Round White Marble Coasters | `001876` |
| `NtpJzvfYjuA0LodO994m` | Set of 4 Wood and Resin Round Coasters | `475824` |
| `PYzFQc2Aoio2TaSFG5Zj` | Teal Pillow | `081066` |
| `p4O6Gf35Hkg54jvQuTVA` | Wood Book Stand | `407589` |

### Homegoods — transaction `iR7EUfNYkbCxKvlP7nz2` (2 items)

| Item ID | Item | SKU |
|---|---|---|
| `ZB3WI0sAvlGcxe0LjgFX` | 7-Stem Pack of Dried Lotus Pods | `948809` |
| `q0Geh9jwyIMKUnDvjUdE` | Dried Lotus Pods | `948809` |

### Wayfair — transaction `KoP50hmljYbRGYcEs9r0` (3 items)

| Item ID | Item | SKU |
|---|---|---|
| `Cg5AntNBEE8NETBowgon` | Dakota Platform Bed with Tall Headboard | `W113072188` |
| `qBxdHWPUOYDEMQ2BuyxA` | Lahjar Speckled Wool Blend Area Rug | `OLAY1077` |
| `Ig8B8YNaxUjaomDRXVxr` | Ruched Crushed Velvet Quilt Set | `RRGE1217` |

### Walmart.com — transaction `wEx1Z6FgXFzr69ssWIt9` (9 items)

| Item ID | Item | SKU |
|---|---|---|
| `KMVFgfh8FcPnnnJjyviG` | Educational Insights Kanoodle 3D Brain Teaser Puzzle Game | `16621221` |
| `w3q8aOu47DRYb7Ob1HCy` | Phase 10 Card Game | `17325824` |
| `Cum5bv5CoziDEoCI4cPJ` | Pressman Rummikub Classic Edition | `882604` |
| `4X2ycvveXminH3gsspLQ` | RoseArt National Parks Gift Set Adult Interlocking Puzzle | `15306457152` |
| `TeGdUTZ27FPknRnHIIev` | Sequence Strategy Game | `23352381` |
| `dVbje8Ph1Y3Q5NjhsjeB` | Spin Master Tetris Board Game | `14474011018` |
| `QyByR9E3bQvUH8DK4UfE` | UNO Card Game | `878142` |
| `uzgJREYu26UmHjz0X4Ff` | USAopoly Tapple Word Game | `401876125` |
| `DBBhlgX87feV3hAtQUR0` | Walmart Delivery Driver Tip |  |

### At Home — transaction `yM4tihvNQZTUdvtU2Cdn` (7 items)

| Item ID | Item | SKU |
|---|---|---|
| `2KNSxgpCwIutJwFSmuY6` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `6YZNkc2Fnu87brr1iVBj` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `SmOdoj7Zpkdqi6QqAwiV` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `amRMWyXUNEzrLW7X4adD` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `i8fAfBLGtZedRIlJLwU1` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `rvSdbSfwCp0E3aVjdjRQ` | Suitcase-Shaped Decorative Pillow | `197154906828` |
| `AE7XHwUD6wpLVauuf63B` | Web Delivery Fee | `191607722249` |

## UI Filter Parity

This list reproduces the Ledger Items tab's `Uncategorized` budget-category filter exactly:

```swift
item.budgetCategoryId == nil
    || item.budgetCategoryId?.trimmingCharacters(in: .whitespaces).isEmpty == true
```

It does not use category-name resolution, transaction fallback, reporting logic, or project-category enablement. Before the repair, running that predicate over the 635 items loaded for Hal Roe returned these 47 item documents and no others. After the repair it returns zero items.

## Repair Applied

The guarded production repair set `budgetCategoryId` to `da556858-1df8-40be-b10c-b15710d7cc9a` (`Furnishings`) on exactly these 47 item documents. It also set each repaired item's `updatedAt` server timestamp. No transaction or unrelated item fields were changed.

Post-write verification confirmed:

- All 47 allowlisted item IDs still exist in Hal Roe and now carry `Furnishings`.
- The Items tab `Uncategorized` predicate returns 0 for Hal Roe.
- Hal Roe now has 634 `Furnishings` items and 1 `Additional Requests` item, totaling the original 635 project items.

The one-time repair is implemented in `scripts/repair-hal-roe-missing-budget-categories.mjs`. It validates the project, category, exact UI result set, linked transactions, and canonical `transaction.itemIds` ownership before it will write.

## Broader 1584 Design Findings

A post-repair read-only account audit found additional category and transaction integrity issues outside Hal Roe. These counts overlap and must not be summed as independent records.

### Same UI Filter

Before the account-wide repair, there were 712 additional project items that matched the same Items tab `Uncategorized` filter:

| Project | Count |
|---|---:|
| Sandra- BAHAMA Unit | 367 |
| Kapcsos Martinique Rental | 316 |
| Hyer's Martinique Rental | 19 |
| Witzenman’s 2nd Home | 8 |
| Jessop's Main Level Design | 2 |

Of those 712 items:

- 699 have a same-project transaction with a real, enabled category and canonical ownership in `transaction.itemIds`. These are deterministic backfill candidates after generating and reviewing project-specific allowlists.
- 13 have no `transactionId`: 6 Witzenman, 6 Hyer, and 1 Sandra. A category cannot be inferred from a transaction; these need an explicit category decision, with transaction association only when the historical evidence supports one.

### Related Integrity Cohorts

The same audit also found:

- 23 project items with no `transactionId` in total. Thirteen are category-blank; the other ten are already valid No Transaction work-queue items under the current model.
- 4 project items whose `transactionId` points to a missing transaction, all in Bradshaws Desert Color Rental.
- 10 Sandra project items whose category is the literal legacy sentinel `uncategorized`, which the UI blank predicate does not match.
- 6 Hyer items whose real category disagrees with the linked transaction's real category.
- 155 Bradshaws items with a real item category linked to a legacy transaction whose category is the `uncategorized` sentinel.
- 222 inventory items that still carry a category despite the current inventory invariant.

These cohorts required separate repair rules and were not part of the initial Hal write. They were handled by the subsequent account-wide repair described below.

## Account-Wide Repair Applied

The guarded migration in `scripts/repair-1584-budget-category-and-transaction-integrity.mjs` repaired the reviewed item and transaction cohorts after validating exact counts, SHA-256 cohort fingerprints, project/category enablement, canonical ownership, receipt evidence, and duplicate references.

### Writes

- Backfilled 699 blank item categories from canonically owning transactions: 610 `Furnishings`, 85 `Additional Requests`, and 4 `Install Supplies`.
- Repaired the 13 blank-category project orphans: 2 were linked to existing receipt transactions by exact SKU, 10 were attached to 5 clearly labeled repair transactions, and 1 confirmed Sandra duplicate was merged and removed.
- Restored 14 additional project-item transaction links: 10 West Elm items to their existing Bradshaws purchase and 4 Amazon items whose stale IDs mapped unambiguously to existing full transaction IDs.
- Replaced the `uncategorized` sentinel on 10 Sandra items and 2 project transactions with `Furnishings`.
- Set `Furnishings` on 10 blank-category legacy Sandra inventory-movement transactions.
- Corrected 6 Hyer item categories to match their canonically owning `Furnishings` transaction.
- Cleared stale categories from 222 inventory items.
- Created 5 repair transactions totaling $476.64 for 10 true project orphans with no historical transaction available. The transaction notes identify every repaired item and state why the transaction exists.
- Merged duplicate Sandra item `i1veNDGZylm87SmuEQay` into `I-1770258762006-q6yt` after matching SKU, purchase price, and photos. The surviving item retained the transaction and received the duplicate's photos and space assignment.

### Independent Verification

An independent production reread after the migration found:

- 4,806 items: 4,327 project items and 479 inventory items.
- 0 project items matched by the exact Items tab `Uncategorized` predicate across every 1584 Design project.
- 0 project items with sentinel, unknown, or project-disabled categories.
- 0 project items without a transaction or referencing a missing transaction.
- 0 item back-references missing canonical `transaction.itemIds` ownership.
- 0 item/transaction category mismatches.
- 0 inventory items carrying a category.
- 0 project transactions with blank or sentinel categories.

## Fix Scope

### Recurrence Prevention

1. Make MCP `bulk_create_items` inherit `budgetCategoryId` from each resolved transaction, matching `create_item`, and reject a project item when no real category can be resolved.
2. Enforce the full `(projectId == null) ↔ (budgetCategoryId == null)` invariant at the MCP and iOS service boundaries, not only in selected callers.
3. Replace direct Set/Clear Transaction field writes with one atomic association operation that updates the item's `transactionId`, inherited category, old/new canonical `itemIds`, and correction lineage. Clearing is allowed: it removes canonical ownership, preserves the real category, and leaves the item in the explicit **No Transaction** work queue.
4. When an existing item is moved to a different transaction, always apply the destination transaction's category. The current add-existing flow preserves a non-null source category and can create a mismatch.
5. Stop persisting `uncategorized` as a category ID. Project destinations must resolve a real category before the write.
6. Cascade ordinary transaction category edits atomically to currently owned items. Generated inventory-movement transaction accounting fields remain frozen.
7. Add MCP bulk-create coverage and iOS tests for create, associate, reassign, clear, inventory-to-project, project-to-project, and transaction-category-edit paths.

### Data Remediation

1. Hal Roe 47-item category backfill: complete and verified.
2. Remaining 699 deterministic blank-category candidates: complete and verified from canonical transactions.
3. Thirteen blank-category project orphans: complete through receipt association, repair transactions, or confirmed duplicate merge.
4. Sentinel, mismatch, missing-transaction, and categorized-inventory cohorts: complete and independently verified.

### Verification Criteria

- The Items tab `Uncategorized` count reaches the reviewed target for every repaired project using the exact Swift predicate.
- Every project item has a real category; every inventory item has no category. A project item may intentionally have no transaction.
- Every linked item transaction back-reference agrees with canonical `transaction.itemIds` ownership after association and movement operations.
- Ordinary item creation, bulk creation, transaction association, and inventory movement cannot persist blank or sentinel categories for project items.
- Repair scripts fail closed when their reviewed result set, project, transaction, ownership, or category preconditions have changed.
