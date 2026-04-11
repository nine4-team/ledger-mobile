# Inventory Source & Naming Conventions
Status: modify (Phase 1 + dynamic label shipped; origin badge and masking still pending)
Last updated: 2026-04-11

> **Shipped**:
> - **Phase 1 — static source label** (2026-04-07). Sale/Return transactions created by `InventoryOperationsService` carry a populated `source` field instead of leaving it blank. Hop 1 (`project_to_business`, legacy) was intentionally untouched — that record lives on the inventory side and isn't displayed in project transaction lists.
> - **Option A — dynamic `[Account Name] Inventory` label** (2026-04-11). `InventoryOperationsService` now takes an `inventoryLabel: String` parameter on `sellToProject`, `returnToInventory`, and `moveBetweenProjects`, defaulting to `"Business Inventory"`. A static helper `InventoryOperationsService.inventoryLabel(for: accountName:)` builds `"[Name] Inventory"` from the account's display name, trimming whitespace and falling back to `"Business Inventory"` when the name is empty. All six production call sites (SellToProjectModal, SellToBusinessModal, ReassignToProjectModal, AddExistingItemsPicker, ItemEntryFlowView, TransactionDetailView) now pass the helper-derived label through `accountContext.account?.name`. Existing tests that pin the default `"Business Inventory"` still pass because of the parameter default; new tests cover both the helper and passthrough for each method.
>
> **Still pending**:
> - Client-facing source masking on invoices / closeout reports (blocked on the unbuilt closeout report spec).
> - Item "From Inventory" badge / origin indicator.
> - Source revert behavior on returns (open design question — should a Return back to inventory revert the displayed source to the original vendor, or keep the inventory label?).

## Summary
When items are sold from business inventory into a project, the resulting sale transaction currently has a blank source field — no label at all. This spec defines how those transactions should be labeled, how the original acquisition source (the store the business bought the item from) should be preserved and surfaced internally, and how source information should be masked in any client-facing context.

## Current Behavior (What Exists Today)

### Sale Transactions (Inventory → Project)
When items move from inventory to a project, a sale transaction is created in the project. Currently:
- **Source field**: blank (empty string)
- **Purchased by**: blank
- **Transaction ID**: structured string like `SALE_[projectId]_business_to_project_[categoryId]` — technically descriptive, but not human-readable and not surfaced as a display name
- **Result**: In a project's transaction list, these show up as unnamed entries alongside clearly labeled transactions (e.g., "Wayfair — $6,349", "Pottery Barn — $5,387", then just "— $3,213" with no source)

### Inventory Purchase Transactions
When items are purchased into inventory, the source is set to the store/vendor name: Homegoods, Ross, Wayfair, Lowe's, etc. This is correct and should remain as-is.

### Items
Individual items in inventory may be associated with a transaction that has a source (the original vendor). When items move to a project, there is currently no indicator on the item that it came from inventory vs. being purchased directly for the project.

## What's Changing

### Staying the Same
- Inventory purchase transactions keep their original vendor as the source (Homegoods, Ross, Wayfair, etc.)
- The underlying data model preserves the original acquisition source — this is never deleted or overwritten
- Transaction-per-category structure within projects stays as-is

### Changing
- **Sale transactions get a proper source label.** When items are sold from inventory to a project, the sale transaction's source field is populated with a clear, identifiable label (see naming options below) instead of being left blank.

### Adding
- **Inventory origin indicator on items.** Items in a project that came from inventory should have a visible marker (tag, badge, or metadata field) so the design team can immediately distinguish them from items purchased directly for the project.
- **Client-facing source masking.** Any context where a client might see transaction or item details (invoices, closeout reports, shared project views) shows only the business inventory label — never the original acquisition vendor.

### Removing
- Nothing removed.

## How It Works

### Transaction Source Label

When a sale transaction is created (items moving from inventory to a project), the source field should be populated with one of these options (dev team decides based on implementation simplicity):

**Option A (preferred):** `[Business Name] Inventory` — dynamically pulls from the account's business name setting. For 1584 Design, this would display as "1584 Design Inventory."

**Option B (fallback):** `Business Inventory` — static label, same for all accounts. Simpler to implement, no dependency on account settings.

**Whichever option is chosen, the label must:**
- Appear in the project's transaction list so these transactions are identifiable at a glance
- Be filterable in transaction filters (the user should be able to filter transactions by this source to see only inventory-sourced items)
- Be consistent across all sale transactions from inventory (same label every time, not varying)

### Original Source Preservation

The original vendor/store where the business acquired the item (Homegoods, Ross, Wayfair, etc.) is valuable data that must never be lost. This is because:
- Items may need to be returned to the original store
- The designer who purchased the item may need to reference where it came from
- Financial tracking of business spending by vendor depends on this data

**Where original source remains visible:**
- Inventory section — purchase transactions always show the original vendor
- Item history/provenance — the item's acquisition history should retain the original source
- Internal/designer views within a project — the original source can be accessible to the design team (e.g., viewable in item detail or item history), since the designer may need this information

**Where original source must be hidden:**
- Invoices generated from the app
- Project closeout reports (see project-closeout-report.md)
- Any view or export that a client could see
- In these contexts, the source should display only as the business inventory label (Option A or B above)

### Inventory Origin Indicator on Items

When an item moves from inventory to a project, it should carry a visible indicator that it came from inventory. This helps the design team distinguish between:
- Items purchased directly for the project (source = "Wayfair", "Pottery Barn", etc., purchased by = client-card or business)
- Items that came from business inventory (source = "[Business] Inventory", originally acquired from some store)

**Implementation options (dev team decides):**
- A tag or badge on the item (e.g., "From Inventory")
- A metadata field on the item recording its origin type (direct purchase vs. inventory transfer)
- The sale transaction's source label itself may be sufficient if items inherit or display their transaction's source

The key requirement is that looking at an item in a project, the team can tell at a glance whether it was inventory-sourced without clicking into transaction details.

## Interaction with Other Specs

- **Item Entry Flow (item-entry-flow.md):** The category-based routing spec defines how items enter inventory and get sold to projects. This naming spec defines what those sale transactions look like once they land in the project.
- **Billing & Invoicing (billing-invoicing.md):** Invoices must use the masked source (business inventory label), never the original acquisition vendor.
- **Project Closeout Report (project-closeout-report.md):** The furnishings breakdown shows items with their project price. Source should display as business inventory, not original vendor. The "savings" narrative already avoids exposing cost basis — this reinforces that.
- **Search Results (search-results.md):** When an inventory-sourced item appears in search results, its project context should show the business inventory source, not the original vendor.

## Open Questions
- Should the business inventory label be configurable by the user (e.g., they could set it to "1584 Design Studio Inventory" or "Design Inventory"), or should it be automatic?
- For items that are returned from a project back to inventory, should the source revert to the original vendor, or should it retain both (original vendor + history of being in a project)?
- Does the inventory origin indicator need to be a distinct visual element (tag/badge), or is the transaction source label sufficient for the team's needs?

---
## Implementation Notes
- The sale transaction source field is currently stored as an empty string. Populating it is likely a straightforward change at the point where sale transactions are created (the sell_items flow).
- If using Option A (dynamic business name), this requires reading from the account/business profile at transaction creation time. If the business name changes later, previously created transactions would retain the old name — this is probably fine (it's a historical record), but worth noting.
- Original source data already exists on the inventory purchase transactions. The question is whether items themselves carry a reference to their originating transaction/source, or if that's looked up through the transaction chain. This affects how easily the original source can be displayed in item detail views.
- Client-facing masking could be handled at the view/export layer (filter what's shown) rather than changing underlying data. This is cleaner than duplicating or overwriting source fields.
