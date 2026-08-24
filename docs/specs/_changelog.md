# Ledger Specs — Changelog

## 2026-08-24
- **Defined and enforced categorized No Transaction items.** Project items may intentionally have no transaction while awaiting correction, but must retain a real category. Item/transaction association changes now update canonical membership and lineage atomically, linked items inherit transaction scope/category, ordinary transaction category/project corrections cascade to owned items, and writers no longer persist the literal `uncategorized` category ID.
- **Aligned MCP returns with the per-batch inventory model.** Return-to-inventory now always creates a new frozen Return transaction, matching iOS; existing Return transaction IDs remain vendor-return-only. Inventory-owned items return to `purchased` status when they come back into stock. Updated `return-and-sale-tracking.md` to restore origin-aware Return versus Sale-to-Inventory routing and source-project budget attribution.

## 2026-08-19
- **Marked purchase handling and inventory intent shipped.** Installed-app QA and a disposable real-Firestore MCP smoke now cover both business-paid branches, intended-project follow-up, authoritative quick-draft transaction linkage, atomic From Inventory promotion, pricing, intent resolution, destination Purchase creation, and lineage. All smoke fixtures were removed afterward.
- **Clarified proto-item rollout status.** Project quick-draft capture and inventory-linked routing are shipped; broader inventory capture, account-wide review, merge, and automation work remains in progress.

## 2026-08-17
- **Started purchase-handling implementation.** Added explicit iOS purchase routing, durable intended project/category fields, no-markup reimbursement pricing, initial From Inventory quick-draft capture, atomic app/MCP inventory-linked promotion, the Business Inventory Planned for Projects queue, and MCP intent/correction/audit tools.
- **Specified explicit handling for business-paid purchases.** The New Transaction flow distinguishes inventory resale from a project purchase temporarily covered by the design business instead of inferring intent from purchaser or category.
- **Added durable inventory destination intent.** Resale purchases may carry one intended project and category while retaining inventory `projectId`/`budgetCategoryId` invariants; project-scoped entry supplies the current project, while unscoped entry may remain general inventory.
- **Defined inventory follow-up and grouping.** Planned-for-project purchases surface waiting, ready, partial, blocked, and unavailable states. One acquisition transaction has at most one intended project/category; mixed destinations are corrected rather than supported.
- **Specified direct reimbursement and MCP cleanup behavior.** Covered project purchases remain in-project with `owed-to-company` and no-markup item pricing. MCP tooling must distinguish real inventory movements from atomic corrections and provide dry-run audits for ambiguous legacy data.
- **Normalized quick-draft transaction association.** `ProtoItem.transactionId` is the single authoritative transaction the eventual item should initially join; `candidateTransactionId` is deprecated. Project drafts linked to inventory transactions convert through one atomic inventory-create-and-sell operation, with the final project Purchase and lineage preserving the acquisition.

## 2026-06-29
- **Clarified returned paid item credits.** Returning an item that was already charged on a paid invoice creates invoice credit demand, not a synthetic transaction. The active model writes an ordinary draft invoice with manual credit lines, copies amount/category from the original paid invoice line, and dedupes by deterministic line ID.
- **Rejected extra credit schema for now.** No new invoice purpose, credit reason enum, credited item field, source invoice field, or source invoice line field is added for this workflow. Deterministic line identity plus invoice notes cover the current need.
- **Blocked net-negative collection semantics.** Credit-only or net-negative invoice selections must not create `paymentToBusiness` transactions because those rows mean money came in from the client.
- **Marked the historical v2 return-credit transaction rule as superseded.** `billing-invoicing-v2.md` now explicitly points readers back to the active no-synthetic-transaction model.

## 2026-05-26
- **Rewrote Billing & Invoicing as the canonical active spec.** Removed the active v1/v2 split in favor of one model: transactions record money movement, invoices demand money, and invoice lines describe demand components.
- **Added manual New Charge invoice lines.** Manual lines cover design fees, retainers, project management fees, storage fees, and other invoice demands that are not backed by prior money movement.
- **Clarified settlement.** Collection is represented by real transactions linked back to invoices or invoice lines; settlement transactions are excluded from the billable pool.
- **Marked historical docs.** `billing-invoicing-v2.md` is now a historical implementation spec, and `project-charges.md` is superseded by manual New Charge invoice lines.
- **Updated dependent docs.** `_index.md`, `project-closeout-report.md`, and `docs/backlog/mcp-invoicing-tools.md` now point at the canonical billing model.
- **Started implementation.** Completed Phase 0 decisions and Phase 1 additive data model work: invoice line IDs, `manual` line source type, optional line source IDs, transaction settlement linkage, and MCP mirror types.

## 2026-05-18
- **Created Proto Item Capture spec.** Added a separate `protoItems` entity for persistent photo-first item intake. Proto items are not real items and do not affect budgets, transactions, invoices, reports, or item counts until converted.
- **Documented capture-first, convert-later workflow.** Project and inventory entry points now support lightweight physical capture, with later review actions to create items, merge with existing items, convert from inventory, or delete.
- **Added implementation plan.** Created `docs/plans/proto-item-capture-implementation.md` covering data model/services, fast capture UI, Needs Review integration, manual conversion, automation assist, and rollout/testing.
- **Updated related specs.** Cross-linked `items.md`, `data-model.md`, `item-entry-flow.md`, `transaction-creation.md`, and `needs-review-tab.md` so new work treats proto item capture as the active item-intake redesign.

## 2026-04-14
- **Restored Sell-to-Inventory as a bidirectional Sale path.** The 2026-04-11 per-batch-sale redesign had removed sell-to-inventory on the "inventory is a store; you don't sell back to it" metaphor. That was a semantic regression: items that originated in a project are never "returning" when the business acquires them — they're being sold. Restored `sellToInventory` in `InventoryOperationsService`; `moveToInventory` now routes per-item based on origin (`item.currentSource != item.source` → Return; otherwise → Sale-to-Inventory). Mixed batches write both transactions atomically. `sellItemsFromProjectToProject` takes the origin-aware first hop too.
- **Direction is type/source-derived, not a field.** A Purchase with an inventory source is inventory → project; a Sale with an inventory source is project → inventory and carries the source accounting `budgetCategoryId`. No new direction field added. The legacy `inventorySaleDirection` enum is honored only on legacy canonical sales.
- **Naming convention.** Display name resolution renders direction explicitly: `"Purchase from [source]"` (inventory → project), `"Sale to [source]"` (project → inventory), `"Return to [source]"` (any Return). Updated in `TransactionDisplayCalculations`; `SearchCalculations.transactionDisplayName` now delegates to it.
- Updated `sale-transactions.md`, `inventory-as-store.md` to reflect Purchase-from-inventory, Sale-to-Inventory, and the shape-derived rule.

## 2026-04-02
- Initial spec setup: created folder structure, index, app map, feedback log
- Created `list-layout.md` spec from first feedback session — desktop app should switch from tile/grid layout to single-column stacked rows (matching the web app)
- Updated `list-layout.md`: added list/grid view toggle as a nice-to-have (Finder-style switcher), confirmed scope is desktop only, mobile is fine as-is
- Created `visual-style.md`: desktop app needs lighter colors and removal of harsh black borders to match web app; mobile app's red needs to be less dingy/gloomy to match web app
- Updated `visual-style.md`: clarified that toggle borders are likely a rendering bug (inconsistent thickness) while card/tile borders are intentional theming to restyle
- Created `search-results.md`: search results need contextual mapping details — item location (project/space/inventory), associated transaction, and purchaser with specific client name
- Updated `search-results.md`: revised approach — search results just need project name added (purchaser can stay as Client/Business), full mapping details belong in the item detail view when you click in

## 2026-04-03
- Created `item-entry-flow.md`: category-based routing replaces the current two-path confusion. Itemized categories (furnishings, accessories, etc.) always flow through inventory first, with an option to immediately sell to a project at entry. Non-itemized expense categories (install, fuel, delivery) skip inventory and go directly to a project. Category selection at the start of transaction creation is the routing fork.
- Created `billing-invoicing.md`: progressive billing system. Items get individual billing statuses (unbilled → invoiced → paid). Users can select approved items from a transaction and generate an invoice for just those items. Marking an invoice as paid cascades to all items on it automatically. Project billing summary shows total cost / invoiced / collected / outstanding. Stretch goal: auto-payment detection via email MCP integration.
- Updated `_app-map.md` with transaction model and billing notes
- Updated `_index.md` with new feature areas: Transactions & Item Entry, Billing & Invoicing
- Updated `visual-style.md` with Typography section: Playfair Display for screen titles, Avenir for all other text (section headers, body, labels, buttons, navigation, dollar amounts). Follows 1584 Design brand guide. Added open questions about font licensing (Avenir is commercial) and specific sizing per platform.

## 2026-04-03 (session 2)
- Created `project-charges.md`: new concept of "service charges" — the third bucket of project costs alongside inventory items and pass-through expenses. Service charges are the business's own fees (design fees, storage fees, bundled service charges). They can be created at project start or anytime during the project, with payment tracking (unpaid → invoiced → paid) that integrates with the existing billing system. Charges can be granular (Design Fee Invoice 1 of 3: $2,500) or bundled (Service & Logistics: $5,000).
- Created `project-closeout-report.md`: client-facing end-of-project report. Four sections: (1) Furnishings breakdown with project price vs. market value and savings total, (2) Project total rolling up furnishings + a single "services & other costs" number (non-itemized costs are NOT broken down individually), (3) Outstanding payments (already included in the total), (4) Optional budget comparison. Report narrative: client saved money, stayed in budget, team delivered exceptional value.
- Updated `_index.md` with new feature areas: Project Charges & Fees, Reporting
- Updated `_feedback-log.md` with session feedback and clarifications

## 2026-04-03 (session 4)
- Created `inventory-source-naming.md`: legacy sale transactions from inventory had a blank source field — spec defines that inventory movement transactions should be labeled "[Business Name] Inventory" or "Business Inventory" (dev team's call). Original acquisition vendor (Homegoods, Ross, Wayfair, etc.) must be preserved and accessible internally but hidden from all client-facing outputs (invoices, closeout reports). Items in a project should carry an indicator that they came from inventory. Verified current state via Ledger API: legacy sale transactions confirmed to have empty source fields.
- Updated `_index.md` with Inventory Source & Naming entry
- Updated `_app-map.md` with sale transaction source field details

## 2026-04-05
- Created `authentication-offline-access.md`: Google Sign-In users never set a password, so they're locked out when Google auth is unavailable (no internet, outage). Spec outlines three possible approaches — backup password prompt, persistent session/cached login, or local credential (PIN/biometric). Key open question: does the app currently work offline at all? Needs dev team input before selecting an approach.
- Updated `_index.md` with new Authentication & Access feature area
- Updated `_feedback-log.md` with session feedback

## 2026-04-03 (session 3)
- Created `item-detail-view.md`: two pieces of feedback — (1) editing UX inconsistency in the web app item detail view (some fields editable inline via pencil icons, others buried in three-dot header menu; should consolidate to a single edit entry point near the content), and (2) item status definitions need clarity. Confirmed four statuses via API: to purchase, purchased, to return, returned. These are designer workflow statuses. Introduced the "two-track status model" — designer workflow status (physical lifecycle) is separate from billing status (financial lifecycle, specced in billing-invoicing.md). Also specced auto-status-on-move: items sold from inventory to a project should auto-set to "Purchased."
- Updated `_index.md` with new Item Detail & Editing feature area
- Updated `_app-map.md` with item detail view and status details
- Updated `_feedback-log.md` with session feedback
