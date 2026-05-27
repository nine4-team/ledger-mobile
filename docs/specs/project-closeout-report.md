# Project Closeout Report
Status: new
Last updated: 2026-05-26

## Summary
A polished, client-facing report generated at the end of a project that tells the full financial story: what was spent across all categories, how much the client saved on furnishings vs. market value, the total project cost including everything, and any outstanding payments still owed. The report's goal is to make the client feel they received incredible value, stayed within budget, and that the design team went above and beyond.

## The Story the Report Tells

The report has a deliberate narrative arc:

1. **Here's what we put in your home** — the furnishings breakdown, showing each item with its project price (what the client paid) and its market value (what it would cost retail). The gap between these is the savings.

2. **Here's how much you saved** — a clear, prominent savings total. The implicit (or explicit) message: this savings covered a significant portion — if not all — of the design fees.

3. **Here's your total project cost** — one number that includes everything: furnishings, design fees, install, expenses, all of it. This is the "bottom line" that the client compares to the budget they agreed to at the start.

4. **Here are a few outstanding items** — any amounts not yet collected. Critically, these are already included in the total above. The client sees that the project is within budget and just needs to settle these remaining balances.

## Report Sections

### Section 1: Furnishings Breakdown

This is the detailed, itemized section. Every item sold to the client from inventory is listed with:

- **Item name**
- **Project price** — what the client is being charged (the price the design team set)
- **Market value** — what the item would cost at retail / market rate

At the bottom of this section:
- **Total project price** (sum of all item project prices)
- **Total market value** (sum of all item market values)
- **Total savings** (market value minus project price) — this is the hero number

If there are multiple itemized categories (e.g., Furnishings, Accessories, Mattresses, Additional Requests), each category gets its own sub-section within the furnishings breakdown, with subtotals per category and a combined total across all itemized categories.

### Section 2: Project Total

A single, clear summary that rolls everything together:

- **Furnishings & items total** — the project price total from Section 1
- **Services & other costs** — a single rolled-up number for everything that is NOT itemized: design fees, install, delivery, fuel, storage, any other expenses, and manual New Charge invoice lines. This is deliberately not broken down line by line — the client sees one number, not a detailed list of every expense category.
- **Overall project total** — furnishings + services & other costs combined. This is the number the client compares to their original budget.

The reason for not breaking down non-itemized costs: the itemized furnishings are where the value story lives (savings, market value comparison). The rest — design fees, install, logistics — are supporting costs that the client already agreed to. Breaking them out invites line-item scrutiny that doesn't serve the narrative. One clean total keeps the focus on the value delivered.

### Section 3: Outstanding Payments

A list of any amounts not yet collected from the client:

- Each outstanding item shows: **description** and **amount owed**
- These can be unpaid manual charges, invoiced-but-not-yet-paid items, or any other balance
- A **total outstanding** amount at the bottom

A clear note (or visual treatment) communicating: "These amounts are already included in the project total above." The client should understand that the project came in at $X, and of that $X, here's what still needs to be settled. They're not additional charges on top.

### Section 4 (Optional): Budget Comparison

If a budget was set at project start:

- **Original budget** — what was agreed to at the beginning
- **Actual project total** — from Section 2
- **Over/under** — did the project come in under budget?

This reinforces the "stayed within budget" message. Only include this if a budget was defined for the project.

## What the Report Does NOT Include

- **Line-by-line breakdown of non-itemized costs** — design fees, install costs, fuel, etc. are rolled into one "services & other costs" number. The client doesn't see "Fuel: $200, Install crew: $3,000, Storage: $800."
- **Internal notes or implementation details** — no billing statuses, no transaction IDs, no references to how things were tracked in the app.
- **Purchaser information** — the report doesn't say "business purchased" or "client purchased." It's just what's in the project and what it cost.

## Generating the Report

The user generates the report from within a project, likely from a "Reports" or "Closeout" action. The report pulls data automatically from:

- All items sold to the project across all itemized categories (for the furnishings breakdown)
- All non-itemized expenses and manual New Charge invoice lines in the project (for the services & other costs total)
- Invoice demand and settlement state (to identify outstanding amounts)
- The project's budget allocation if one was set (for the budget comparison)

The report is generated as a downloadable document (PDF likely — the team already downloads invoices for external use). It should be designed/formatted to feel professional and on-brand, consistent with 1584 Design's visual identity (Playfair Display headers, Avenir body text, brand colors — see `visual-style.md`).

## Open Questions
- What format should the report be? PDF seems most likely for a client-facing document, but confirm.
- Should the report include the 1584 Design logo / branding? If so, where does the logo asset come from?
- Should the "savings" narrative be explicit text (e.g., "Your savings of $12,400 more than covered your design fees") or just presented as numbers and let the designer explain it verbally?
- Should the outstanding payments section include due dates or just amounts?
- Is there a scenario where the report is generated mid-project (progress report) rather than only at closeout? If so, should there be a "draft" or "in-progress" version?
- Should the furnishings breakdown show item images, or just names and prices?
- For the budget comparison section — where is the original budget number stored? Is it in the project settings, or does it need a new field?
- What happens if there are no outstanding payments? Does Section 3 just not appear, or does it say something like "All payments collected — thank you!"?

---
## Implementation Notes
- Report generation needs to aggregate data across multiple sources: items (with project price and market value), expenses, manual New Charge invoice lines (see `billing-invoicing.md`), invoice settlement state, and budget allocations
- PDF generation will require a template/layout engine — the report needs to look polished, not just be a data dump. Consider whether the existing invoice generation infrastructure can be extended or if this needs a separate report template.
- Market value on items: confirm this field exists on items today. The app map notes project price and market value as concepts, but the exact field names and availability need discovery.
- The "services & other costs" total is calculated by summing: all non-itemized category expenses + manual New Charge invoice lines. This crosses multiple data sources.
- Outstanding amounts are identified from sent invoice demand minus linked settlement transactions.
- The report should be regeneratable — if an outstanding payment comes in after the report was first generated, the user should be able to generate an updated version
