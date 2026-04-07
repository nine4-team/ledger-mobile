# Property Management Report
Status: modify
Last updated: 2026-04-06

## Summary
An existing report in Ledger (under Finances → Reports) that provides property management companies with an overview of items placed in their properties. This report is separate from the client-facing closeout report — it's intended for the property manager's records, not the end client.

## Current Behavior (What Exists Today)
[needs discovery — exact current layout and fields TBD]

The report currently shows item-level detail including SKU numbers for each item. The report lives under Finances → Reports in the app.

Based on what's known about item data in Ledger, the report likely shows some combination of:
- Item name
- SKU
- Source/vendor
- Purchase price / project price
- Market value
- Space/room assignment
- [exact fields shown need discovery from the codebase]

## What's Changing

### Staying the Same
- The report itself continues to exist under Finances → Reports
- All other item details shown in the report remain as-is
- The report's purpose (giving property management a record of what's in the property) stays the same

### Changing
- **SKU is removed from the report.** Property management doesn't need to see internal SKU numbers for items. SKU is an inventory/sourcing detail that's useful internally but has no value to a property manager receiving this report.

### Adding
- Nothing new

### Removing
- **SKU per item** — no longer displayed in the property management report

## How It Works
When the property management report is generated, each item's listing omits the SKU field entirely. The SKU still exists on the item in Ledger — it's just not surfaced on this particular report. Other reports (closeout report, invoices, internal views) are not affected by this change.

## Open Questions
- What is the full list of fields currently shown per item on this report? [needs discovery from the codebase]
- Are there other fields that should also be hidden from property management (e.g., purchase price, vendor/source)? Or is it just SKU?
- Is this report downloadable (PDF, etc.) or just an in-app view? Or both?
- Can the user customize which fields appear on the report, or is the field list fixed?
- Is there any scenario where property management *would* need the SKU (e.g., for warranty claims or returns)?

---
## Implementation Notes
- This is a display-level change on the report template/view — SKU data on the item model is unchanged
- If the report is generated as a PDF or downloadable document, the template needs to be updated to exclude the SKU column/field
- If the report is an in-app view, the list/table layout needs to drop the SKU column
