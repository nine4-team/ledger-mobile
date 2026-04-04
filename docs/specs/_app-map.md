# App Map: Ledger
Last updated: 2026-04-03

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
- Projects have one transaction per budget category (e.g., one Furnishings transaction per project that accumulates items over time)
- Transactions can be purchase transactions (business buys items into inventory) or sale transactions (items sold from inventory to a project)
- Categories come in two types: **itemized** (individual items tracked with detail — furnishings, accessories, additional requests, mattresses) and **non-itemized/expense** (costs logged at transaction level — install, fuel, delivery). [Full category list needs discovery]

### Item Entry (Current — Being Redesigned)
- **Path A (being removed for itemized categories):** Items added directly to a project, marked as "business purchased, client owes"
- **Path B (becoming the standard for itemized categories):** Items enter inventory via purchase transaction, then sold/moved to a project
- Non-itemized expenses currently [needs discovery — unclear how these are handled today]

### Invoicing (Current)
- Ledger can generate downloadable invoice documents
- No payment tracking or collection in-app
- Invoices are downloaded and attached to external payment software for collection
- No item-level billing status exists today

### Who Purchased
- Transactions track who made the purchase: Business or Client
- Most common scenario: business purchases, client owes reimbursement
- Also common: client card used directly (logged for tracking, no reimbursement needed)
- Rare: client purchased something the business should have covered

## Data Model Summary
Based on available MCP tools, key entities include: Items, Transactions, Projects, Spaces, Accounts, Budget Categories. Relationships between these are [needs discovery].

## Navigation Flow
[Needs discovery — the app has desktop and web versions with potentially different navigation patterns]

## Notes
- No codebase access yet. App map is based on user descriptions. Will reconcile when codebase is available.
- The Ledger MCP connector is available, which suggests the app's data model includes: items, transactions, projects, spaces, accounts, and budget categories.
