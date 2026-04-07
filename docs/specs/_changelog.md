# Ledger Specs — Changelog

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
- Created `inventory-source-naming.md`: sale transactions from inventory currently have a blank source field — spec defines that they should be labeled "[Business Name] Inventory" or "Business Inventory" (dev team's call). Original acquisition vendor (Homegoods, Ross, Wayfair, etc.) must be preserved and accessible internally but hidden from all client-facing outputs (invoices, closeout reports). Items in a project should carry an indicator that they came from inventory. Verified current state via Ledger API: sale transactions confirmed to have empty source fields.
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
