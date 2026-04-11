# Ledger — Specification Index
Last updated: 2026-04-10

## Status Key
- [current] — Already built, keeping as-is
- [modify] — Already built, needs changes
- [new] — Not yet built
- [shipped] — Spec implemented (note any deferred stretch goals inline)
- [remove] — Currently exists, should be removed
- [tbd] — Needs further discussion

## Feature Areas

### Transactions & Item Entry
- [shipped] [Item & Expense Entry Flow](item-entry-flow.md) — Category-based routing: itemized categories go through inventory, non-itemized expenses go directly to projects (commit 322cf420, 2026-04-07)
- [modify] [Inventory Source & Naming](inventory-source-naming.md) — Transaction source labeling for inventory sales, original source preservation, and client-facing source masking. **Phase 1 shipped 2026-04-07** (sale transactions now carry "Business Inventory" source label). Client-facing masking, item origin badges, and dynamic business-name labels still pending.

### Billing & Invoicing
- [shipped] [Billing & Invoicing](billing-invoicing.md) — Item-level billing status (unbilled → invoiced → paid), selective mid-project invoicing, invoice-level payment cascade. Auto-payment detection (email/MCP stretch goal) **deferred**. Shipped 2026-04-07.

### Lists & Layout
- [shipped] [List Layout](list-layout.md) — macOS item and transaction lists default to single-column stacked rows via `Dimensions.listColumns` platform branch. Shipped 2026-04-03 (commit 2358be7b). List/grid toggle nice-to-have deferred.

### Visual Style
- [modify] [Visual Style](visual-style.md) — Color palette, border/outline styling, and typography across all platforms. **Shipped**: status colors brightened (2026-04-03); macOS hairline borders + dark-mode-adaptive soft border color (2026-04-10); full typography — Avenir Next workhorse + Playfair Display screen titles (bundled Google Fonts variable TTF, wired into pbxproj + UIAppFonts + ATSApplicationFontsPath, runtime-verified via CTFontManager) (2026-04-10). **Still pending**: web-app color verification and audit of direct `.font(.system(...))` call sites.

### Project Charges & Fees
- [new] [Project Charges](project-charges.md) — Service fees, design fees, and planned costs created within a project (distinct from inventory items and pass-through expenses)

### Reporting
- [new] [Project Closeout Report](project-closeout-report.md) — Client-facing end-of-project report showing furnishings breakdown with savings, total project cost, and outstanding payments

### Item Detail & Editing
- [shipped] [Item Detail View](item-detail-view.md) — Consistent editing UX, auto-status on inventory-to-project move, two-track status (workflow + billing). Shipped across 2026-04-07 → 2026-04-10: auto-status, toolbar status capsule, Notes + Details pencil-per-section edit, kebab menu reduction, and `Billing` DetailRow alongside `Status`. One open question remains on auto-status edge cases.

### Search
- [shipped] [Search Results](search-results.md) — Contextual mapping details on search rows and item detail. Project name surfaced on search cards; item detail hero now shows Project, Purchaser, Budget Category, Transaction, and Space. Purchaser row shipped 2026-04-10.

### Bug Fixes
- [shipped] [Project List Bugs](project-list-bugs.md) — Business Inventory card on the Projects screen showed "0 items · 0 transactions" because `InventoryContext` was only activated from the Inventory tab. Fixed by activating it at `MainTabView` for the whole signed-in session. Shipped 2026-04-07.

### Authentication & Access
- [tbd] [Authentication & Offline Access](authentication-offline-access.md) — Google Sign-In users have no fallback when Google auth is unavailable; need a workaround for offline/degraded scenarios
