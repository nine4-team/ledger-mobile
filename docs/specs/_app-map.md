# App Map: Ledger
Last updated: 2026-06-23

## Overview
Ledger is an inventory and transaction management app for design teams. It exists as both a web app and a macOS desktop app. The app tracks items (inventory) and transactions across projects and spaces, with budgeting and reporting features.

## Screen Inventory

### Items & Transactions Lists (Desktop)
- **What it does**: Displays lists of items and transactions across the app (within projects, spaces, and top-level views)
- **Key elements**: [needs discovery — current layout uses a tile/grid format with multiple items per row in the desktop app; the web app uses a single-column stacked list layout]
- **Navigates to/from**: [needs discovery]
- **Status**: partially-mapped

### Items & Transactions Lists (Web)
- **What it does**: Same data as the desktop app, displayed in a single-column stacked list layout (one item per row)
- **Key elements**: [needs discovery — noted as the preferred layout by the team]
- **Navigates to/from**: [needs discovery]
- **Status**: partially-mapped

## Transaction & Billing Model (Current Understanding)

### Transaction Structure
- Projects have normal project transactions plus per-batch inventory movement transactions. Inventory movement transactions are not long-lived aggregators; their accounting fields are frozen while `itemIds` tracks current active membership.
- Transactions can be purchase transactions (business buys items into inventory, or a project buys items from inventory), return transactions, or Sale-to-Inventory transactions (business acquires project-originated items into inventory)
- Categories come in two types: **itemized** (individual items tracked with detail — furnishings, accessories, additional requests, mattresses) and **non-itemized/expense** (costs logged at transaction level — install, fuel, delivery). [Full category list needs discovery]

### Item Entry (Current — Being Redesigned)
- **Path A (being removed for itemized categories):** Items added directly to a project, marked as "business purchased, client owes"
- **Path B (becoming the standard for itemized categories):** Items enter inventory via purchase transaction, then sold/moved to a project
- **Proto item capture (new redesign):** Physical objects can be captured first as persistent photo groups (`protoItems`) from project, inventory, or transaction context, then converted later into real items, existing receipt-created items, or inventory-to-project flows. See `proto-item-capture.md`.
- Non-itemized expenses currently [needs discovery — unclear how these are handled today]

### Invoicing
- Ledger stores project-scoped invoices as demands for money.
- Invoice lines can reference existing items, existing transactions, or manual **New Charge** lines such as design-fee milestones.
- Transactions remain records of actual money movement. Marking an invoice collected creates one normal Fee transaction linked by `settlementInvoiceId`.
- Ad-hoc invoices can include pre-existing transactions and manual charges in the same invoice.
- Item/transaction billing state is derived from invoice membership and settlement links; there is no item-level billing status field.

### Inventory Movement Source (Inventory → Project)
- When items are sold from inventory to a project, a Purchase-from-inventory transaction is created in the project at `projectPriceCents`
- If an item has no project price, the user is asked what to sell it for before the movement is committed, and that value is saved as `projectPriceCents`
- Project-to-project movement is a two-hop atomic flow: source project exits to business inventory at project price, then destination project buys from inventory at project price
- Project-to-business-inventory movement uses purchase price
- **Historical state:** The source field on legacy sale transactions was **blank** (empty string)
- **Legacy transaction IDs** follow the pattern `SALE_[projectId]_business_to_project_[categoryId]` or `SALE_[projectId]_project_to_business_[categoryId]` — structured but not human-readable
- **purchasedBy** field may also be blank on historical inventory movement transactions
- **Being changed:** Source should be populated with "[Business Name] Inventory" or "Business Inventory" — see inventory-source-naming.md

### Who Purchased
- Transactions track who made the purchase: Business or Client
- Most common scenario: business purchases, client owes reimbursement
- Also common: client card used directly (logged for tracking, no reimbursement needed)
- Rare: client purchased something the business should have covered

### Item Detail View (Web)
- **What it does**: Shows all details for a single item — fields, status, images, location, history
- **Key elements**:
  - Item fields with inline pencil icons for some fields (edit in place)
  - Three-dot overflow menu in top-right header containing: "Edit Details", "Status", [other items need discovery]
  - Item status display showing one of four values: To Purchase, Purchased, To Return, Returned
  - [Other sections/fields need discovery — what exactly is shown on this screen]
- **Navigates to/from**: Accessed by tapping/clicking an item from any list view (project items, inventory, search results, etc.)
- **Status**: partially-mapped

## Item Status Model
Items have four statuses (confirmed via Ledger API):
- **To Purchase** — item identified but not yet bought
- **Purchased** — item has been bought by the business
- **To Return** — item needs to be returned
- **Returned** — item has been returned

These are designer-facing workflow statuses tracking the physical lifecycle of an item. Billing state is derived from invoices and settlement transactions — see billing-invoicing.md.

When items are moved from inventory to a project, the status is set to "Purchased."

## Data Model Summary
Key entities include: Items, ProtoItems, Transactions, Invoices, InvoiceLines, Projects, Spaces, Accounts, and Budget Categories. ProtoItems are separate from Items and do not affect budgets, inventory, transactions, invoices, reports, or item counts until resolved.

## Navigation Flow
[Needs discovery — the app has desktop and web versions with potentially different navigation patterns]

## Notes
- No codebase access yet. App map is based on user descriptions. Will reconcile when codebase is available.
- The Ledger MCP connector includes items, transactions, invoices, projects, spaces, accounts, and budget categories.
