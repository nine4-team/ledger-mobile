# Ledger — Specification Index
Last updated: 2026-08-31

## Status Key
- [current] — Already built, keeping as-is
- [modify] — Already built, needs changes
- [new] — Not yet built
- [shipped] — Spec implemented (note any deferred stretch goals inline)
- [remove] — Currently exists, should be removed
- [tbd] — Needs further discussion
- [superseded] — Replaced by another spec; preserved for historical context

## Feature Areas

Central cross-feature program tracking:
[Ledger Accounting Redesign](../plans/ledger-accounting-redesign/README.md).

### Invoice-Centered Project Accounting (Target Redesign)
- [modify] [Invoice-Centered Project Accounting](invoice-centered-project-accounting.md) — **Approved target direction; not implemented.** Project Purchases/Returns record real client money movement, paired Transfers are the sole non-cash project Transaction, inventory Transactions record real 1584 inventory money movement, and 1584-paid project demand lives as Items, Expenses, and Fees in Invoicing until whole-Invoice collection creates one lump-sum project Purchase. Defines scope ownership, routing, collection, paid-history immutability, and the two-segment no-double-count budget model.
- [new] [Client Identity and Project Transfers](client-identity-and-project-transfers.md) — **Core direction and net-zero budget reallocation approved; edge decisions remain.** Globally limits Transaction types to scope-relative Purchase/Return plus project-only Transfer. Adds an account-scoped Client entity and required `project.clientId`. Same-Client bulk Item Transfer bypasses Business Inventory and atomically creates linked source/destination records; eligibility uses Client IDs, never names.
- [modify] [Inventory Item Invoicing and Return Lifecycle](inventory-item-invoicing-lifecycle.md) — **Approved target direction; not implemented.** Defines user-facing Item charges and credits plus hidden occurrence provenance for sell, live repricing, pre-Invoice return, live-Invoice return, paid return, resale, project-origin acquisition, return-to-project, same-Client direct Transfer, cross-Client sale through inventory, correction, and vendor return stories.

### Sale Transactions & Inventory (Current Implementation)
- [modify] [Inventory Movement Transactions](sale-transactions.md) — **Current shipped container; target replacement documented.** Per-batch inventory movements currently write project-side Purchase/Sale/Return Transactions. Origin-aware price and provenance rules remain required, but the target redesign moves the project-side financial effect to Item charges/credits in Invoicing. Category reclassification remains approved for the current model until cutover.
- [new] [Inventory as a Store](inventory-as-store.md) — **Active.** Conceptual model: business inventory is treated like any vendor/store. Items in inventory have `budgetCategoryId == null`. Project → inventory is origin-aware. Every item write keeps project price at or above purchase cost; project-destination movements prompt only when neither price is positive.
- [superseded] [Canonical Sales](canonical-sales.md) — **Legacy.** The original aggregator-based sale model. Preserved for historical reads and the dual-read sign convention path. New work should reference `sale-transactions.md` instead.

### Transactions & Item Entry
- [shipped] [Correct Transaction and Its Items](2026-08-30-correct-transaction-and-its-items.md) — Atomically corrects one ordinary transaction and its complete active item set between projects or Business Inventory while preserving membership, detaching incompatible spaces, and writing correction lineage. Generated movements and referenced history fail closed. MCP shipped and production-smoke-verified 2026-08-30; iOS UI exposure is deferred.
- [shipped] [Purchase Handling and Inventory Intent](purchase-handling-and-inventory-intent.md) — **Current shipped behavior; partially replaced in the target redesign.** Separates business-paid resale acquisitions from direct project reimbursements and defines inventory intent. The invoice-centered target retires the business-paid physical-goods `project_reimbursement` path: those goods always enter Business Inventory before becoming project Item charges.
- [modify] [Vendor Credits](vendor-credits.md) — **Superseded target proposal; retained as problem evidence.** D-001/D-007 prohibit its fourth Credit Transaction type. Actual vendor money returned is a scope-relative Return; non-cash cancellation/account credit is tracked by O-028.
- [shipped] [Agent Transaction Taxonomy Guide](agent-transaction-taxonomy-guide.md) — **Current-client guide with a migration warning.** Normal shipped writes use `purchase`/`return`, system workflows create `sale`/`paymentToBusiness`, and legacy values are read-compatible only. Target clients must move to the invoice-centered boundary only after its trusted writers and migration ship.
- [modify] [Item Creation and Accounting Link](proto-item-capture.md) — **Core UX approved; target writer and hard-cutover import pending.** One wizard puts the former proto capture fields first and writes a real Item. Project Items remain Unaccounted For until connected to a client-paid Purchase or billable Item occurrence. Current Firebase proto behavior stays unchanged before source freeze; the target imports it and has no proto runtime dual-read.
- [modify] [Item & Expense Entry Flow](item-entry-flow.md) — **Current routing with target replacement documented.** Proto capture remains relevant. The invoice-centered target sends 1584-paid itemized goods through Business Inventory, 1584-paid non-itemized costs to Expenses in Invoicing, and direct client-paid costs to project Transactions.
- [shipped] [Inventory Source & Naming](inventory-source-naming.md) — Transaction source labeling for inventory sales, original source preservation, and client-facing source masking. Two-field source split: `item.source` (original vendor, immutable) + `item.currentSource` (immediate source, mutable). Reports and search cards read `currentSource`. All items backfilled 2026-04-11.

### Billing & Invoicing
- [modify] [Billing & Invoicing](billing-invoicing.md) — **Current implementation model; target replacement documented.** Its transaction/line sources, partial collection, and category-grouped settlement behavior must not be extended. The invoice-centered target uses whole-Invoice collection, one actual lump-sum Purchase, and frozen attached source allocations. Returned paid Items still create credit demand rather than synthetic Transactions.
- [superseded] [Invoice Transaction Redesign Draft](invoice-transaction-redesign-draft.md) — Historical July 2026 exploration; replaced by the invoice-centered target specs.
- [superseded] [Invoice Redesign Change Plan](invoice-redesign-change-plan.md) — Historical companion to the July draft; do not execute. A new implementation plan must be derived after the open target-state decisions are resolved.
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
- [new] [Account Discovery and Workspace Selection](account-discovery-and-workspace-selection.md) — **Canonical target selection contract.** A stable Principal sees a readiness-labeled, visibility-safe Account list and must explicitly choose an Account. Remembered state is ordering convenience only; selection is local intent, never membership or authorization. Auth provider, offline lease, physical activation, app/MCP wiring, and target schema remain separately gated.
- [new] [Financial Access Controls](financial-access-controls.md) — **Active planned spec.** Member-specific company financial visibility: full, limited-by-fee-category, or none. Intended first use is employees who can see selected fee categories such as Kitchen Fees without seeing broader design-fee revenue or hidden-fee invoices.
- [tbd] [Authentication & Offline Access](authentication-offline-access.md) — Google Sign-In users have no fallback when Google auth is unavailable; need a workaround for offline/degraded scenarios
