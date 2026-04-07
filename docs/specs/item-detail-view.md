# Item Detail View
Status: modify
Last updated: 2026-04-03

## Summary
The item detail view shows all information about a single item — its details, status, images, location, and history. This spec covers two areas: (1) making the editing experience more consistent and accessible, and (2) clarifying item status definitions and automation.

## How It Works (Current — Web App)
When viewing an item's details in the web app, the user sees all item information laid out in a detail view. Editing is currently split across two different interaction patterns:

- **Inline edit (pencil icons):** Some fields have a small pencil icon to the right of the field. Tapping the pencil lets the user edit that field directly in place. The user likes this pattern.
- **Three-dot menu (top-right header):** Other fields — including "Edit Details" and "Status" — are only accessible through a three-dot overflow menu in the top-right corner of the screen header.

This inconsistency is frustrating. The user has to remember which fields can be edited inline vs. which require navigating to the header menu. It also buries important actions (like changing status) in a place that feels disconnected from the content.

### Current Item Statuses
Items have four possible statuses, confirmed via the Ledger API:

- **To Purchase** — item has been identified/specified but not yet ordered or bought
- **Purchased** — item has been bought by the business
- **To Return** — item needs to be returned
- **Returned** — item has been returned

These statuses track the **designer's physical workflow** — the lifecycle of acquiring and managing the item. They are distinct from the billing/invoicing status (unbilled → invoiced → paid) specced in [billing-invoicing.md](billing-invoicing.md), which tracks the **financial lifecycle** of collecting payment from the client.

## What's Changing

### Staying the Same
- The item detail view itself (the layout of information sections and fields)
- The inline pencil icon pattern for fields that already support it — this is the preferred editing interaction
- The four status values (to purchase, purchased, to return, returned) — these are good as designer-facing workflow statuses

### Changing
- **Editing entry point:** Instead of burying edit actions in the three-dot header menu, provide a single edit entry point closer to the content. The preferred approach: a pencil/edit icon next to the "Details" section header that puts all fields in that section into edit mode at once. This replaces the need to go to the three-dot menu for "Edit Details."
- **Status editing:** Status should have its own dedicated, easily accessible edit control — not buried in the header overflow menu. Exact placement TBD (could be near the status display itself, could be a prominent control at the top of the detail content area), but it should not require opening a menu in the header.
- **Three-dot menu scope:** With editing and status pulled out to more accessible locations, the three-dot menu in the header should be reduced to truly secondary actions only (e.g., delete, share, archive — actions you don't do frequently). [Exact remaining menu items need discovery.]

### Adding
- **Auto-status on inventory-to-project move:** When an item is moved/sold from inventory into a project, its status should automatically be set to "Purchased." Currently this requires a manual update, and items frequently slip through without being updated (the team just did a cleanup pass to fix this). This automation removes a maintenance burden and keeps data accurate for reporting.

## Two Status Tracks: Designer Workflow vs. Billing

Items effectively have two parallel status dimensions:

1. **Designer workflow status** (this spec): to purchase → purchased → to return → returned. Tracks the physical lifecycle — has the item been ordered, has it arrived, does it need to go back?

2. **Billing status** (see [billing-invoicing.md](billing-invoicing.md)): unbilled → invoiced → paid. Tracks the financial lifecycle — has the client been billed for this item, have they paid?

These serve different audiences and answer different questions. A designer checking their shopping list cares about workflow status. The person handling invoicing cares about billing status. An item that is "Purchased" (designer bought it) might still be "Unbilled" (client hasn't been invoiced yet) — those are independent facts.

**Guiding principle:** Keep these two tracks visually and conceptually separate in the UI. Don't merge them into one status field or force the user to think about billing when they're doing design workflow, or vice versa.

**Naming:** Both tracks cannot be called "Status" — that creates ambiguity ("what's the status?" could mean either). Working direction is to keep the designer workflow as "Status" (since that's what the team already knows) and give the billing track a distinct label like "Billing" or "Payment." Example of how this might read on an item:

**Status:** Purchased
**Billing:** Unbilled

Names are NOT finalized — still needs workshopping. The important decision is that they're two separate, clearly labeled tracks, not the names themselves.

## Open Questions
- **Cross-platform scope:** This feedback came from the web app. Should the same editing UX changes apply to desktop and mobile, or spec those separately? (Assuming web-first for now.)
- **Exact placement of status control:** The user wants status out of the three-dot menu and more accessible, but the exact location hasn't been determined. Options include: near the status display itself, a prominent chip/badge that's tappable, or a dedicated section at the top of the detail area.
- **Exact placement of section edit button:** "Next to Details" was the instinct — needs design exploration for where exactly the edit icon sits relative to the section header.
- **What remains in the three-dot menu?** Once editing and status are pulled out, what secondary actions still live there? [Needs discovery of current menu items.]
- **Should the two status tracks (workflow + billing) be visually co-located on the item detail view, or in separate sections?** The user's instinct is separate, but this needs design exploration to see what feels right in practice.
- **Naming for the two status tracks:** Working direction is "Status" (designer workflow) and "Billing" or "Payment" (financial), but names are not finalized. Needs further workshopping — the team wants to make sure the labels feel intuitive and don't create confusion.
- **Auto-status edge cases:** When items are moved to a project, should the auto-set to "Purchased" happen in all cases, or only when the item's current status is "To Purchase"? (E.g., if an item is already marked "To Return," moving it to a different project probably shouldn't reset it to "Purchased.")
- **Status definitions and reporting impact:** The team acknowledges the status definitions need more clarity, especially around how they interact with reporting. For example, does "Purchased" in reports mean "the business has bought this" or "the client has paid for this"? The two-track model (workflow status vs. billing status) should resolve this ambiguity, but it needs to be validated against actual reporting requirements once the closeout report spec is more detailed.

---
## Implementation Notes
- The Ledger API currently supports four item statuses: "to purchase", "purchased", "to return", "returned" (confirmed via the `list_items` endpoint filter).
- Auto-status on inventory-to-project move would need to hook into the sell/move flow — when `sell_items` is called or an item's project assignment changes, the status should update automatically.
- The billing status track (unbilled → invoiced → paid) is a new field being specced separately in billing-invoicing.md — it does not exist in the current data model.
