# Item & Expense Entry Flow
Status: modify
Last updated: 2026-05-18
Implemented: 2026-04-07

## Summary
How items and expenses get into a project. Currently there are two overlapping paths for physical items (direct-to-project vs. inventory-first), which creates confusion. This spec replaces them with a single, category-based routing system: the category you select at transaction creation determines whether the flow goes through inventory or goes directly to the project.

**2026-05-18 redesign note:** The inventory-first routing model remains the financial/accounting model for real items, but item intake is moving toward a capture-first flow using persistent proto items. See [proto-item-capture.md](proto-item-capture.md). New implementation should avoid requiring full item details during field capture.

## Current Behavior (What Exists Today)

There are two ways to get costs into a project:

**Path A — Direct to project:** User creates a transaction inside a project, adds items, marks them as "business purchased, client owes." The items land in the project immediately. They never touch inventory.

**Path B — Inventory first:** User creates a transaction in inventory (business purchases items). Items sit in inventory. Later, the user sells/moves selected items to a project. This creates a sale transaction in the project.

Both paths can be used for the same type of item (e.g., furnishings), which leads to inconsistency in how items are tracked and makes it unclear which flow to use.

## What's Changing

### Staying the Same
- Transactions are still organized by budget category within a project (one transaction per category, e.g., one furnishings transaction that accumulates items over time)
- Items still have detail fields (name, cost, vendor, etc.) when they belong to itemized categories
- The concept of "who purchased" (business vs. client) is preserved

### Changing
- **Path A (direct to project) is eliminated for physical/itemized items.** All furnishings, accessories, additional requests, and other itemized categories must flow through inventory first, even if they're immediately sold to a project in the same action.
- **Category selection becomes the routing decision.** The first step of transaction creation is choosing a category. The category type (itemized vs. non-itemized) determines which flow the user enters — no manual choice of "inventory or project?"

### Adding
- **Immediate sell-to-project option at inventory entry.** When entering items into inventory under an itemized category, the user is prompted: "Do you want to sell this entire transaction to a project?" or "Do you want to select specific items to sell to a project?" This makes inventory → sell feel like one step, not two, while still routing through the consistent pipeline.
- **Direct-to-project flow for non-itemized expense categories.** Categories like install, fuel, delivery, and other service/expense categories skip inventory entirely. These aren't physical goods — they go straight to a project. The flow asks: which project? Who purchased it?
- **Proto item capture as the lightweight intake path.** For physical items where details are unknown, the designer can create proto items from project or inventory context, then resolve them into real items later.

### Removing
- **The ability to add itemized items directly to a project as "business purchased, client owes."** This path goes away. If it's an itemized category, it goes through inventory (even if it's immediately sold onward).

## How It Works

### Step 1: Category Selection
When creating a new transaction, the user first selects a budget category. Categories are classified as one of two types:

**Itemized categories** — categories where individual items are tracked with detail (name, cost, vendor, images, etc.). Examples: Furnishings, Additional Requests, Accessories, Mattresses.

**Non-itemized (expense) categories** — categories where costs are logged at the transaction level, not as individual trackable items. Examples: Install, Fuel, Delivery, Miscellaneous Expenses.

The category type determines which flow comes next.

### Step 2a: Itemized Category Flow (Inventory First)
If the user selects an itemized category:

1. User enters item details as they do today (name, cost, vendor, quantity, images, etc.)
2. Items are created in inventory, tied to a purchase transaction
3. At the bottom of the entry flow, the user sees a prompt:
   - **"Sell entire transaction to a project"** — all items on this transaction get sold to a specific project. User selects the project.
   - **"Select items to sell to a project"** — user picks which items to sell now and which to leave in inventory. User selects items, then selects the project.
   - **"Keep in inventory"** — items stay in inventory for now. Can be sold to a project later through the existing sell flow.
4. If sold to a project, items land in the project's transaction for that category (e.g., the project's single Furnishings transaction)

### Step 2b: Non-Itemized Category Flow (Direct to Project)
If the user selects a non-itemized/expense category:

1. User enters expense details: amount, description, vendor/payee, date, receipt/documentation
2. User selects which project this expense belongs to
3. User indicates who purchased it:
   - **Business purchased** (most common) — the business fronted the cost, client owes reimbursement
   - **Client purchased** (common) — the client's card was used, logged for project tracking but no reimbursement needed
   - **Client purchased, business owes** (rare) — client covered something the business should have paid for
4. The expense goes directly into the project under the appropriate category — no inventory step

### Why This Design

The two flows map to a real-world distinction: physical items that the business stocks, tracks, and sells to clients are fundamentally different from service expenses that are just costs to pass through. Forcing expenses through "inventory" would create phantom inventory entries for things like gas and labor. And having two ways to enter physical items creates confusion about which to use. The category-based fork handles both cleanly without the user needing to think about the system architecture — they just pick the category and the right flow appears.

## Open Questions
- What is the full list of categories and which are itemized vs. non-itemized? [needs discovery from current category list]
- If a category is currently used both ways (sometimes itemized, sometimes not), does it need to be split into two categories or should the user be able to override the default flow?
- When selling items to a project at entry time, should the user also be able to split items across multiple projects in one action (e.g., 5 items to Project A, 3 to Project B)?
- Should there be a confirmation step before selling, or is the prompt at the bottom of entry sufficient?

---
## Implementation Notes
- Category metadata will need a flag or type field distinguishing itemized vs. non-itemized categories to drive the routing logic
- The "sell at entry" prompt is a UI addition to the existing inventory transaction creation flow — the underlying sell mechanism can reuse the existing sell_items pipeline
- Path A removal means any existing "business purchased, client owes" items already in projects (not from inventory) may need a migration path or legacy handling
