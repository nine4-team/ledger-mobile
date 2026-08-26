# Ledger — Specification Index
Last updated: 2026-08-25

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
- [modify] [Inventory Movement Transactions](sale-transactions.md) — **Active; category reclassification approved, implementation pending.** Per-batch inventory movement transactions: inventory → project writes a Purchase at project price; project → inventory writes an origin-aware Return or Sale-to-Inventory at purchase price; project → project uses purchase price for the source exit and project price for the destination Purchase. The trusted item-price trigger may adjust an eligible Purchase amount/subtotal until the existing paid-invoice freeze boundary. A dedicated correction will allow the entire uncollected Purchase to move to another project-enabled itemized category while atomically updating current items. `itemIds` tracks current active membership. Replaces the canonical-sale aggregator model.
- [new] [Inventory as a Store](inventory-as-store.md) — **Active.** Conceptual model: business inventory is treated like any vendor/store. Items in inventory have `budgetCategoryId == null`. Project → inventory is origin-aware. Every item write keeps project price at or above purchase cost; project-destination movements prompt only when neither price is positive.
- [superseded] [Canonical Sales](canonical-sales.md) — **Legacy.** The original aggregator-based sale model. Preserved for historical reads and the dual-read sign convention path. New work should reference `sale-transactions.md` instead.

### Transactions & Item Entry
- [shipped] [Purchase Handling and Inventory Intent](purchase-handling-and-inventory-intent.md) — Separates business-paid resale acquisitions from direct project reimbursements, persists intended project/category across delayed inventory sales, defines the inventory follow-up queue and one-destination invariant, and normalizes quick-draft transaction association and inventory conversion. Shipped and runtime-verified 2026-08-19.
- [new] [Vendor Credits](vendor-credits.md) — **Proposed.** A vendor-issued negative transaction, beginning with cancellation credits for selected lines on a mixed purchase. Distinct from physical returns; legacy returns remain unchanged pending separately approved evidence-backed migration.
- [shipped] [Agent Transaction Taxonomy Guide](agent-transaction-taxonomy-guide.md) — Canonical short guide for AI/MCP clients: normal writes use `purchase`/`return`, system workflows create `sale`/`paymentToBusiness`, legacy `fee`/`expense`/`to inventory` are read-compatible only, and `metadata.categoryType` owns itemization/routing.
- [modify] [Proto Item Capture](proto-item-capture.md) — **Active partially shipped redesign.** Project capture, From Inventory marking, authoritative transaction selection, and atomic inventory-linked conversion are shipped. Broader inventory capture, review, merge, and automation work remains.
- [modify] [Item & Expense Entry Flow](item-entry-flow.md) — Category-based routing remains the financial model, but physical item intake is being redesigned around proto item capture.
- [shipped] [Inventory Source & Naming](inventory-source-naming.md) — Transaction source labeling for inventory sales, original source preservation, and client-facing source masking. Two-field source split: `item.source` (original vendor, immutable) + `item.currentSource` (immediate source, mutable). Reports and search cards read `currentSource`. All items backfilled 2026-04-11.

### Billing & Invoicing
- [modify] [Billing & Invoicing](billing-invoicing.md) — **Active canonical spec.** Transactions record money movement; invoices demand money; invoice lines can source from items, existing transactions, fee installments, or invoice-only manual adjustments. Manual adjustments use the hidden `Other Client Charges & Credits` settlement category. Collection is tracked by linking real money-movement transactions back to invoices. Returned paid items create ordinary created-invoice credit lines, not synthetic credit transactions.
- [superseded] [Billing & Invoicing v2](billing-invoicing-v2.md) — **Historical implementation spec.** Shipped 2026-04-21; superseded as the active product spec by `billing-invoicing.md` on 2026-05-26.

### Lists & Layout
- [shipped] [List Layout](list-layout.md) — macOS item and transaction lists default to single-column stacked rows via `Dimensions.listColumns` platform branch. Shipped 2026-04-03 (commit 2358be7b). List/grid toggle nice-to-have deferred.

### Visual Style & UX
- [shipped] [Visual Style](visual-style.md) — Color palette, border/outline styling, and typography across all platforms. Ships across 2026-04-03 → 2026-04-11: status colors brightened; macOS hairline borders + dark-mode-adaptive soft border color; atRiskBar/overflowBar retinted to rust family; Avenir Next workhorse + Playfair Display screen titles; icon call-site audit complete (70 SF Symbol sites kept, 5 text sites migrated to new `Typography.badge`/`microLabel` tokens or inline `.custom("AvenirNext-*", …)`). Web-parity framing dropped as stale.

- [new] [Field Tooltips](ui/tooltips.md) — Info tooltips on non-obvious fields across the app. `(i)` icon next to labels, bottom sheet with plain-language explanation. Centralized content registry.

### Project Charges & Fees
- [superseded] [Project Charges](project-charges.md) — Historical proposal for a standalone charge entity. Active behavior is now covered by fee installments and invoice lines in `billing-invoicing.md`.

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
- [new] [Financial Access Controls](financial-access-controls.md) — **Active planned spec.** Member-specific company financial visibility: full, limited-by-fee-category, or none. Intended first use is employees who can see selected fee categories such as Kitchen Fees without seeing broader design-fee revenue or hidden-fee invoices.
- [tbd] [Authentication & Offline Access](authentication-offline-access.md) — Google Sign-In users have no fallback when Google auth is unavailable; need a workaround for offline/degraded scenarios
