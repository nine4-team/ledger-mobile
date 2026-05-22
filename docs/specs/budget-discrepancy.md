# Budget Display Discrepancy (Cached vs. Live)
Status: [modify]
Last updated: 2026-04-06

## Summary
The project list page and the inside-project budget views show different "spent" totals for the same project. The project list uses a cached budget summary stored on the project document, while the Finances tab and inside-project Overall Budget bar compute spend live from transactions. These two sources are out of sync, creating conflicting numbers that undermine trust in the budget data.

## The Bug

### What the user sees
- **Project list page (main page)**: Shows the Overall Budget bar with one "spent" number (e.g., $122,642 for Hyers)
- **Inside project → Overall Budget bar**: Shows a different, lower "spent" number (e.g., $111,898 for Hyers)
- **Inside project → Finances tab → Budget sub-tab**: Matches the inside-project number, not the main page number

The main page number is always *higher* than the inside-project number.

### What's actually happening (confirmed via API)
Two different data sources power the budget display:

1. **Cached budget summary** (`budgetSummary` on the project document): A denormalized snapshot of budget and spend data. This is what the project list page reads. It does not recalculate when transactions change — it's a stale cache.

2. **Live budget computation** (computed from transactions): This is what the Finances tab and inside-project budget bar use. It sums actual transaction amounts in real time.

### Where the gap lives
The discrepancy traces entirely to the **Furnishings** category, which is the only category with `categoryType: "itemized"`. All other categories (Fuel, Kitchen, Install, Storage & Receiving, Design Fee) match between cached and live.

| Project | Cached Furnishings | Live Furnishings | Gap |
|---|---|---|---|
| Hyer's Martinique Rental | $90,171.25 | $82,079.85 | $8,091.40 |
| Witzenman's 2nd Home | $107,487.06 | $102,809.90 | $4,677.16 |
| Jessop's Main Level | $33,390.35 | $31,658.75 | $1,731.60 |

**Likely cause**: The "itemized" category type calculates spend differently than other categories — probably from item cost data rather than transaction amounts. When items are returned, cancelled, or have price adjustments applied via transactions, the transaction-based live calculation reflects the change but the cached item-based calculation does not update.

### Hidden categories in the cached total
The cached budget summary also includes spend from categories that don't appear on the Finances page:

- **Games and Entertainment**: $125.00 spent in cache (no budget allocated, not shown in Finances). The user confirmed they moved all Games and Entertainment items into Furnishings — there are now zero transactions in this category. But the cache still counts the $125 because it was never recomputed after the recategorization.
- **Uncategorized**: $2,494.97 spent (not shown in Finances as a visible category). These are 9 items across 2 legacy system-generated "Sale" transactions representing inventory-to-project moves. The items were recategorized to Furnishings at the item level on April 6, 2026, but the legacy synthetic Sale transactions retain `budgetCategoryId: "uncategorized"` because inventory-movement transactions inherit the item's category at the time of the move and don't update when the item is later recategorized. See "Inventory movement category bug" below.
- **Additional Requests**: $0 spent on Hyers, but $12,289.65 on Witzenman (has $0 budget, shown in live but contributes to cache)

These hidden amounts inflate the cached total further beyond just the Furnishings gap.

### Inventory movement category bug
In legacy canonical-sale data, when items were moved between business inventory and a project, the system generated synthetic transactions with IDs like `SALE_{projectId}_business_to_project_{categoryId}`. The budget category on these transactions was set at the time of the move based on the item's category at that moment. If the item had no category (uncategorized), the synthetic transaction is permanently uncategorized — recategorizing the item later does not update the transaction.

**Confirmed on Hyers**: 9 items totaling $2,494.97 net ($2,509.96 in, $14.99 out) were moved from inventory without a category. Items were recategorized to Furnishings on April 6, 2026, but the legacy Sale transactions still show as uncategorized in the live budget, and the spend does not roll into the Furnishings total.

**Items affected** (all now tagged Furnishings at item level, but still uncategorized at transaction level):
- Black rectangular coffee table ($309.10)
- Black & ivory wool rug runner 3'x10' ($200.00)
- 10'x14' Ochre speckled wool rug ($799.99)
- Black/brown large framed agate wall art x2 ($49.99 each)
- Broccoli-style greenery in black rectangle long pots ($19.99)
- King dark olive green diamond quilt ($160.00)
- Round wood nightstand with drawer ($129.99)
- Hey hi hello coir doormat ($14.99 — moved out of project)

## What's Changing

### Bug to fix
- **Cached budget summary is stale** → The project list page must either (a) use the same live computation as the Finances page, or (b) the cache must be reliably invalidated and recomputed whenever transactions are created, updated, cancelled, or items are returned/price-adjusted.
- **Itemized category spend calculation differs between cache and live** → Both paths must use the same formula. Need to determine which is correct: the item-cost-based number or the transaction-based number. The transaction-based number is more likely correct since it reflects actual money movement.

### Inventory movement bug to fix
- **Legacy synthetic Sale transactions don't update when items are recategorized** → When an item's budget category changes after it was moved from inventory to a project under the legacy canonical-sale model, the system-generated Sale transaction does not update to reflect the item's current category. Recategorizing the item has no effect on the transaction, leaving spend permanently orphaned in "uncategorized."

### Display issue to address
- **Hidden categories not visible in Finances** → If uncategorized spend and spend in categories with no budget allocation (like Games and Entertainment) count toward the Overall Budget total, they should be visible somewhere in the Finances breakdown. Currently they're phantom spend — included in the total but not shown in any line item, so the category numbers don't add up to the overall.

### New feature: Uncategorized filter in category filter
- **Add "Uncategorized" as an option in the budget category filter** (on the Items tab, Transactions tab, and anywhere else categories can be filtered). This lets users quickly find items and transactions that haven't been assigned a budget category, so they can clean them up. Currently there's no way in the UI to surface uncategorized transactions — users have no way to know they exist or to audit them.

### New feature: "Sale" option in transaction type filter
- **Expose inventory movement transaction filters** on the Transactions tab. Legacy Sale transactions and new Purchase-from-inventory / Sale-to-Inventory / Return-to-inventory records should be auditable without implying that inventory-to-project moves are `type: "Sale"`. The available type options should include current transaction types plus a clear inventory-movement filter.

## Impact on Real Projects (Hyers Specifically)

For Hyer's Martinique Rental, the numbers as of April 6, 2026:

| Source | Total Spent | Remaining |
|---|---|---|
| Project list (cached) | ~$122,518 | ~$9,482 |
| Finances (live) | $114,426 | $17,574 |

The real remaining budget is likely closer to **$17,574** (the live number), not the ~$9,482 the main page suggests. That's nearly double the breathing room.

**Design Fee status**: $24,511 received out of $32,650 budgeted = **$8,139 still owed by client**.

## Open Questions
- Which calculation is the source of truth for Furnishings spend — item costs or transaction amounts? If an item is returned, should its cost still count as "spent"?
- Should categories with $0 budget but nonzero spend (like Games and Entertainment) appear on the Finances page?
- Is the cache update mechanism broken, or was it never built to handle transaction updates on itemized categories?
- Should the project list page just use the live computation instead of a cache? (Performance tradeoff — live computation requires reading all transactions per project)

### Resolved
- ~~Should uncategorized transactions be visible as a line item on the Finances page, or should every transaction be required to have a category?~~ → **Decision**: Add "Uncategorized" as a filter option in the category filter so users can find and recategorize orphaned transactions. (April 6, 2026)

---
## Implementation Notes
- The cached data lives in `budgetSummary` on the project document, with per-category breakdowns in `budgetSummary.categories`
- The `categoryType: "itemized"` on Furnishings is the distinguishing factor — all "general" and "fee" type categories match between cached and live
- The live budget endpoint computes from 92 transactions on the Hyers project
- The cache was last updated at timestamp 1775498984 (around April 4, 2026)
- Categories with `enabled: false` (like uncategorized) still appear in the cached summary but are excluded from the live budget's visible category list
