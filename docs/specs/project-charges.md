# Project Charges (Service Fees & Planned Costs)
Status: new
Last updated: 2026-04-03

## Summary
A way to create and track service fees, design fees, and other planned charges within a project. These are the business's own fees for services rendered — not reimbursable expenses the business fronted, and not inventory items sold to the client. Each charge has a set amount, a name, and a payment status. Charges can be created at project setup or added anytime during the project.

## The Three Buckets of Project Cost

This feature establishes the third type of cost that flows through a project:

1. **Inventory items** (already specced in `item-entry-flow.md`) — physical goods purchased into inventory and sold to the client. Tracked individually with detail. Flow through the inventory-first pipeline.

2. **Pass-through expenses** (already specced in `item-entry-flow.md`) — costs the business fronted on behalf of the client (fuel, install crew labor, delivery fees). Have receipts, vendors, and a "who purchased" field. Flow direct-to-project under non-itemized categories.

3. **Service charges** (this spec) — the business's own fees for its services. Design fees, storage fees, project management fees, or bundled service charges. No receipt, no vendor, no "who purchased" — the business is the provider. Amount is set deliberately by the team, not driven by an external cost.

All three types roll into the project total. All three participate in the billing system (unbilled → invoiced → paid). But they have different data entry needs and different roles in the project story.

## How It Works

### Creating a Charge

The user can create project charges at any point during a project — at initial setup or mid-project as needs arise. To create a charge:

1. User navigates to a project and accesses a "Charges" or "Service Fees" section
2. User taps "Add Charge" (or similar action)
3. User enters:
   - **Name** (required) — a descriptive label for the charge. Examples: "Design Fee - Invoice 1 of 3", "Storage & Logistics Fee", "Installation Coordination", "Design Fee - Final"
   - **Amount** (required) — the dollar amount for this charge
   - **Description / Notes** (optional) — any additional context. Examples: "Covers storage, delivery coordination, and install scheduling", "Phase 1 design services per contract"
   - **Category** (optional, TBD) — whether charges should be categorized or if they're their own top-level grouping [see Open Questions]
4. The charge is created with a payment status of **unpaid**

### Bundling vs. Itemizing

The user decides how granular to be per project. Some examples:

- **Granular:** "Design Fee Invoice 1 of 3: $2,500" + "Design Fee Invoice 2 of 3: $2,500" + "Design Fee Invoice 3 of 3: $2,500" + "Storage Fee: $800" + "Install Coordination: $1,200"
- **Bundled:** "Design Fees (Full): $7,500" + "Service & Logistics: $5,000"
- **Single lump:** "Project Services: $12,500"

There's no right or wrong way — the system supports whatever level of detail the team wants for a given project. The charges are just named line items with amounts.

### Payment Tracking

Each charge has a payment status that follows the same model as item billing (see `billing-invoicing.md`):

- **Unpaid** — the charge has been created but the client hasn't been billed or hasn't paid yet
- **Invoiced** — the charge has been included on an invoice sent to the client
- **Paid** — payment has been received and confirmed

The user can update the status manually, or charges can be included in invoices through the same selective invoicing flow that works for items — select charges to include on an invoice, generate it, and when the invoice is marked paid, all charges on it cascade to "paid" automatically.

### Charges in the Billing System

Service charges integrate with the existing billing and invoicing system (see `billing-invoicing.md`):

- When generating an invoice, the user can select service charges alongside items and expenses to include on the same invoice
- A single invoice to the client might include: 3 furnishing items + 1 install expense + Design Fee Invoice 2 of 3 — all on one document
- The project billing summary includes service charges in its totals (total cost, total invoiced, total collected, total outstanding)

### Viewing Charges

Within a project, charges are visible in a dedicated section (or alongside other costs — exact placement TBD). The user can see at a glance:

- Each charge's name and amount
- Each charge's payment status (unpaid / invoiced / paid)
- A summary: total charges, total collected, total outstanding

## What's Changing

### Adding
- **Service charges as a project-level concept** — a new type of cost entry distinct from inventory items and pass-through expenses
- **Charge creation flow** — ability to add named, fixed-amount charges to a project at any time
- **Payment status tracking on charges** — same unbilled → invoiced → paid pipeline as items
- **Charges in invoicing** — service charges can be included alongside items on invoices
- **Charges in project totals** — service charges roll into the overall project cost, billing summary, and closeout report

### Removing
- Nothing explicitly removed

## Open Questions
- Should charges live under their own top-level section in the project (e.g., "Service Fees" alongside "Furnishings", "Install", etc.), or should they be a new budget category type? Leaning toward a dedicated section since they don't behave like budget categories.
- Should there be a way to set up a "charge template" for common fee structures? (e.g., "3-phase design fee" that auto-creates three charges with names and amounts) — probably a future nice-to-have, not MVP.
- Can a charge be edited after creation? (e.g., the amount changes because scope changed) Likely yes, but should editing be restricted once the charge has been invoiced?
- Should charges have a date field (e.g., "due date" or "expected billing date") to help the team plan when to invoice?
- How does this relate to the existing budget category system? Are service charges included in budget allocations, or are they outside the budget (since the budget typically refers to what's being spent on furnishings/materials)?

---
## Implementation Notes
- A new `ProjectCharge` entity (or similar) is needed: name (string), amount (decimal), description (optional string), payment status (enum: unpaid, invoiced, paid), project reference, date created, date paid
- Charges need to be referenceable by the Invoice entity — same as items, so invoices can span items + expenses + charges
- The project billing summary calculation needs to include charges: total cost = sum of items + expenses + charges
- Consider whether charges should be editable via the Ledger MCP (would need new endpoints: create_charge, update_charge, list_charges)
