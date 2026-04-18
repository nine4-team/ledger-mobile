# Ledger — Specification Index
Last updated: 2026-04-11

## Status Key
- [current] — Already built, keeping as-is
- [modify] — Already built, needs changes
- [new] — Not yet built
- [shipped] — Spec implemented (note any deferred stretch goals inline)
- [remove] — Currently exists, should be removed
- [tbd] — Needs further discussion
- [superseded] — Replaced by another spec; preserved for historical context

## Feature Areas

### Sale Transactions & Inventory (Per-Batch Redesign)
- [new] [Sale Transactions](sale-transactions.md) — **Active.** Per-batch sale transactions: every user sell action creates one new immutable Sale transaction. Replaces the canonical-sale aggregator model.
- [new] [Inventory as a Store](inventory-as-store.md) — **Active.** Conceptual model: business inventory is treated like any vendor/store. Items in inventory have `budgetCategoryId == null`. Project → inventory is a Return, not a Sale.
- [superseded] [Canonical Sales](canonical-sales.md) — **Legacy.** The original aggregator-based sale model. Preserved for historical reads and the dual-read sign convention path. New work should reference `sale-transactions.md` instead.

### Transactions & Item Entry
- [shipped] [Item & Expense Entry Flow](item-entry-flow.md) — Category-based routing: itemized categories go through inventory, non-itemized expenses go directly to projects (commit 322cf420, 2026-04-07)
- [shipped] [Inventory Source & Naming](inventory-source-naming.md) — Transaction source labeling for inventory sales, original source preservation, and client-facing source masking. Two-field source split: `item.source` (original vendor, immutable) + `item.currentSource` (immediate source, mutable). Reports and search cards read `currentSource`. All items backfilled 2026-04-11.

### Billing & Invoicing
- [shipped] [Billing & Invoicing](billing-invoicing.md) — Item-level billing status (unbilled → invoiced → paid), selective mid-project invoicing, invoice-level payment cascade. Auto-payment detection (email/MCP stretch goal) **deferred**. Shipped 2026-04-07.

### Lists & Layout
- [shipped] [List Layout](list-layout.md) — macOS item and transaction lists default to single-column stacked rows via `Dimensions.listColumns` platform branch. Shipped 2026-04-03 (commit 2358be7b). List/grid toggle nice-to-have deferred.

### Visual Style & UX
- [shipped] [Visual Style](visual-style.md) — Color palette, border/outline styling, and typography across all platforms. Ships across 2026-04-03 → 2026-04-11: status colors brightened; macOS hairline borders + dark-mode-adaptive soft border color; atRiskBar/overflowBar retinted to rust family; Avenir Next workhorse + Playfair Display screen titles; icon call-site audit complete (70 SF Symbol sites kept, 5 text sites migrated to new `Typography.badge`/`microLabel` tokens or inline `.custom("AvenirNext-*", …)`). Web-parity framing dropped as stale.

- [new] [Field Tooltips](ui/tooltips.md) — Info tooltips on non-obvious fields across the app. `(i)` icon next to labels, bottom sheet with plain-language explanation. Centralized content registry.

### Project Charges & Fees
- [new] [Project Charges](project-charges.md) — Service fees, design fees, and planned costs created within a project (distinct from inventory items and pass-through expenses)

### Reporting
- [new] [Project Closeout Report](project-closeout-report.md) — Client-facing end-of-project report showing furnishings breakdown with savings, total project cost, and outstanding payments

### Item Detail & Editing
- [shipped] [Item Detail View](item-detail-view.md) — Consistent editing UX, auto-status on inventory-to-project move, two-track status (workflow + billing). Shipped across 2026-04-07 → 2026-04-10: auto-status, toolbar status capsule, Notes + Details pencil-per-section edit, kebab menu reduction, and `Billing` DetailRow alongside `Status`. One open question remains on auto-status edge cases.

### Search
- [shipped] [Search Results](search-results.md) — Contextual mapping details on search rows and item detail. Project name surfaced on search cards; item detail hero now shows Project, Purchaser, Budget Category, Transaction, and Space. Purchaser row shipped 2026-04-10.

### Developer & Debug
- [shipped] [Copy Entity ID](ui/copy-entity-id.md) — `Copy ID` kebab-menu action on items and transactions (list cards + detail views). Uses shared `Clipboard` helper for iOS/macOS. Shipped 2026-04-11.

### Bug Fixes
- [shipped] [Project List Bugs](project-list-bugs.md) — Business Inventory card on the Projects screen showed "0 items · 0 transactions" because `InventoryContext` was only activated from the Inventory tab. Fixed by activating it at `MainTabView` for the whole signed-in session. Shipped 2026-04-07.

### Authentication & Access
- [tbd] [Authentication & Offline Access](authentication-offline-access.md) — Google Sign-In users have no fallback when Google auth is unavailable; need a workaround for offline/degraded scenarios
