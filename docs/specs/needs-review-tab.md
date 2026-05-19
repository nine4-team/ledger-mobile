# Needs Review Tab
Status: modify
Last updated: 2026-05-18

## Summary
The Needs Review tab surfaces items, proto items, and transactions that need attention, but currently displays them as a flat, context-free list. When the user taps into an item, they can't tell which client it's for, what project it lives in, or what they're supposed to do with it. This is the same problem the previous search bar had — results stripped of their surrounding context. The fix is to group the list by project and add breadcrumb navigation to item details.

Proto item capture makes this tab a cross-workflow cleanup work queue: captured photo groups appear here until a reviewer creates an item, merges the capture into an item, sells from inventory, or dismisses the capture. Item Drafts must also appear in their owning project, inventory, or transaction Items context; Needs Review is not their canonical home. See [proto-item-capture.md](proto-item-capture.md).

## Current Behavior (What Exists Today)

- The Needs Review tab shows a flat list of items/transactions that need attention (flagged for review, incomplete data, pending decisions, etc.)
- Tapping into an item opens its detail view, but the detail view does not show which client it belongs to, which project it's part of, or what budget category it falls under
- There is no grouping or visual organization on the list — items from different projects and inventory are interleaved with no separation
- The user has to mentally track or navigate away to figure out where an item belongs and what action to take
- This mirrors the context problem that existed with the previous search bar: results appeared in isolation with no way to understand their place in the larger picture

## What's Changing

### Staying the Same
- The Needs Review tab still surfaces items that need attention — the core concept of a review queue is correct
- Items still open to their detail view when tapped

### Changing
- **Flat list → grouped by project.** The Needs Review list is reorganized into visual sections, one per project, so the user can immediately see which project each batch of items belongs to. Each section header shows the project name (and ideally the client name).
- **Context-free item detail → breadcrumb trail.** When the user taps into a needs-review item, the detail view shows a navigable breadcrumb path above the item content. The breadcrumb shows the item's full location: **Client > Project > Category** (e.g., "Smith Residence > Living Room Redesign > Furnishings"). Each segment of the breadcrumb is tappable, navigating the user up to that level.

### Adding
- **Project-grouped list layout** on the Needs Review tab with visual dividers between project sections
- **Inventory / Unassigned section** — items that are in inventory (not yet sold to a project) or that have no project association get their own section, visually distinct from the project groups. This makes it immediately obvious which items are floating and may need to be assigned.
- **Proto item sections** — unresolved Item Drafts are shown alongside incomplete items/transactions, grouped by project, intended project, inventory/unassigned, or candidate transaction. These rows point to the same drafts users can also find under the relevant Items surface.
- **Proto item resolution actions** — create item, merge into existing item, sell from inventory, or dismiss.
- **Breadcrumb navigation** on the item detail view showing Client > Project > Category, with each level tappable
- **Assign-to-project action (TBD)** — for items in the unassigned/inventory section, a way to assign them to a project directly from the Needs Review tab without navigating away. [Details need further discussion — see Open Questions]

### Removing
- The flat, ungrouped list layout

## How It Works

### The Needs Review List (Grouped View)

When the user opens the Needs Review tab, they see items organized into sections:

**Section: [Project Name] — [Client Name]**
Each project that has items needing review gets its own section. The section header shows the project name and client name. Within each section, items are listed as they are today (name, thumbnail if available, brief description of why it needs review).

**Section: Inventory / Unassigned**
Items that are in inventory but not associated with a project, or items that need review but have no project context, appear in a separate section at the bottom (or top — placement TBD). This section serves as a clear signal: "these items are floating — they may need to be assigned somewhere."

The grouping gives the user an instant visual map of their review workload organized by project, instead of a jumbled list where items from five different projects are mixed together.

**Proto item rows**
Item Drafts render as capture groups rather than normal item rows. The row should emphasize the photos, capture context, source hint, and next action. An item draft row does not open the normal item detail view because it is not an item yet; it opens a resolve workflow.

Needs Review uses the same unresolved Item Drafts that appear under Project Items, Inventory Items, and Transaction Items. Resolving or dismissing a draft from Needs Review removes it from both the global queue and its contextual Item Drafts sub-tab.

### Item Detail View (With Breadcrumb)

When the user taps an item from the Needs Review list, the detail view now includes a breadcrumb trail at the top of the screen:

**Client Name > Project Name > Category Name**

For example: "Johnson Family > Master Bedroom Refresh > Furnishings"

Each segment is tappable:
- Tapping **Client Name** navigates to the client's project list (or client detail, if that exists)
- Tapping **Project Name** navigates to the project view
- Tapping **Category Name** navigates to the transaction/category within the project

For inventory items (not yet in a project), the breadcrumb would show: **Inventory > [Category]** — or simply "Inventory" if there's no category context.

This breadcrumb also applies to items accessed from search results, resolving the same context problem that existed with the previous search bar.

### Assigning Unassigned Items

For items in the Inventory / Unassigned section, the user needs a way to assign them to a project. The exact mechanism needs further discussion, but possibilities include:
- A "Move to Project" or "Assign to Project" button on the item detail view
- A long-press or swipe action on the list item itself
- A batch-select mode where the user checks multiple items and assigns them to a project at once

This connects to the existing sell-to-project flow (see `item-entry-flow.md`) — assigning from Needs Review may just be a shortcut to the existing sell mechanism.

## Open Questions
- **What triggers "needs review"?** What are all the reasons an item ends up in the Needs Review tab? Is it incomplete data, pending approval, items flagged manually, transactions without a project, or something else? [needs discovery — exact criteria TBD]
- **Proto item ordering:** Should unresolved captures appear before incomplete transactions, or should each project section interleave all review types by date?
- **Reviewer mode:** Should proto item resolution be optimized for desktop/macOS first, where a VA or remote reviewer is most likely to work?
- **Assignment flow:** Can items in needs-review genuinely arrive without a project, or is the data always there and just not displayed? If some truly arrive unlinked, what's the right assignment flow from this screen? Does it use the existing sell-to-project pipeline, or is it a simpler "link to project" action?
- **Sort within project groups:** Within each project section, how should items be sorted? By date added? By urgency/type of review needed? By category?
- **Section order:** Should project sections be sorted alphabetically, by number of items needing review (most first), or by most-recently-updated project?
- **Empty state:** When all items are reviewed, what does the tab show? A "You're all caught up" message?
- **Badge/count:** Should each project section header show a count of items needing review? (e.g., "Smith Residence — 4 items")
- **Breadcrumb on other screens:** Should the breadcrumb pattern be adopted globally on all item detail views (not just from Needs Review), or only when navigating from Needs Review and search?
- **Previous search bar issue:** The feedback references the "same issue we had with the previous search bar." Is the search bar context problem already resolved, or does the breadcrumb solution need to be applied to search results too?

---
## Implementation Notes
- The grouped list requires fetching project/client associations for each needs-review item, which may not be loaded in the current flat list query
- Breadcrumb data (client → project → category → item) needs to be available on the item detail view — this may require passing additional context when navigating from the Needs Review list, or resolving the full chain from the item's relationships
- Consider whether the breadcrumb component should be a shared/reusable view that can be added to item detail, search results, and any other context where items appear outside their natural project home
- The "assign to project" action from Needs Review would likely reuse the existing sell_items or item-move pipeline rather than creating a new mechanism
