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
