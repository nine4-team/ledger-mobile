# Ledger — Specification Index
Last updated: 2026-04-05

## Status Key
- [current] — Already built, keeping as-is
- [modify] — Already built, needs changes
- [new] — Not yet built
- [remove] — Currently exists, should be removed
- [tbd] — Needs further discussion

## Feature Areas

### Transactions & Item Entry
- [modify] [Item & Expense Entry Flow](item-entry-flow.md) — Category-based routing: itemized categories go through inventory, non-itemized expenses go directly to projects
- [modify] [Inventory Source & Naming](inventory-source-naming.md) — Transaction source labeling for inventory sales, original source preservation, and client-facing source masking

### Billing & Invoicing
- [modify] [Billing & Invoicing](billing-invoicing.md) — Item-level billing status (unbilled → invoiced → paid), selective mid-project invoicing, invoice-level payment cascade, auto-payment detection stretch goal

### Lists & Layout
- [modify] [List Layout](list-layout.md) — Item and transaction list display format across the app (desktop vs. web parity)

### Visual Style
- [modify] [Visual Style](visual-style.md) — Color palette, border/outline styling, and typography (Playfair Display + Avenir brand fonts) across all platforms

### Project Charges & Fees
- [new] [Project Charges](project-charges.md) — Service fees, design fees, and planned costs created within a project (distinct from inventory items and pass-through expenses)

### Reporting
- [new] [Project Closeout Report](project-closeout-report.md) — Client-facing end-of-project report showing furnishings breakdown with savings, total project cost, and outstanding payments

### Item Detail & Editing
- [modify] [Item Detail View](item-detail-view.md) — Consistent editing UX (pull edit/status out of header menu), item status definitions, auto-status on inventory-to-project move, two-track status model (designer workflow vs. billing)

### Search
- [modify] [Search Results](search-results.md) — Add contextual mapping details to search results (location, transaction, purchaser/client)

### Authentication & Access
- [tbd] [Authentication & Offline Access](authentication-offline-access.md) — Google Sign-In users have no fallback when Google auth is unavailable; need a workaround for offline/degraded scenarios
