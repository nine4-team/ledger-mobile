# Needs Review Tab
Status: modify
Last updated: 2026-05-18

> **Target boundary:** O-063 owns the target review reasons, grouping and
> contextual navigation. The real-Item/Link model supersedes all recurring
> ProtoItem/Quick Draft conversion language below. Existing source behavior is
> the bucketed Transaction queue, not the flat mixed list described by the old
> proposal. Legacy capture conversion is migration-only; source `isComplete`
> and Cloud Functions are not target review authority.

## Target Review Contract

Preserve the Review section, visible context/counts, local query and eight
existing sort choices: purchase date newest/oldest, amount highest/lowest,
creation date newest/oldest and source A–Z/Z–A. Keep exact stable-ID detail
routing and app-wide find scrolling. Distinguish globally caught up, selected
group empty, query-no-match, incomplete/stale evidence and unavailable detail.
O-063 decides how those controls apply to the target's typed review reasons and
Project/Client/Inventory grouping, including archived and unassigned evidence.

Each target row must explain why attention is needed using canonical evidence,
not a generic stored completeness bit, missing-array heuristic or automatic
"unassigned means sell" inference. Resolving a row invokes its owning Item
Link, physical-placement, receipt/accounting correction or other approved
workflow. Context includes current Client/Project/Inventory, category/Space and
visible accounting links; tappable breadcrumb destinations remain O-063.

A new target Item is already a real Item: no convert/promote/merge-from-proto
writer is added to Review. O-018/O-019 own legacy capture reconciliation;
O-032 owns Transaction posting/readiness. Permanently rejected offline work
retains its separate O-051 recovery policy; this screen cannot silently
acknowledge or discard it. Financial visibility applies before local counts,
rows or resolution context are exposed. Search/review share approved readers
and owning commands, not duplicated review-specific business logic.

Resolution acceptance must exercise the exact selected identity and approved
destination, including unavailable/denied/canceled paths, and cite the owning
workflow's verification. It does not require Review-specific backend writers.
Financial resolution context remains subject to O-060.

## Summary
### Caller-Supplied MCP Ingestion Evidence

Account for existing MCP Transaction metadata readback, exact ingestion-status
filtering, metadata supplied at creation, and status updates during triage.
Source fields include origin/status, email ID/subject/inbox, confidence/reason,
order number and related Transaction IDs. The inspected source has no email
intake, matching or deduplication service; none is implied by these fields.

Preserve raw imported values as correlated source evidence. O-069 decides
preserve/redesign/retire for the supplied-metadata capability. O-063 decides which
typed reasons and transitions belong in target review; O-065 governs ordinary
Transaction mutations and O-060 financial visibility. Untrusted caller claims
such as `auto_matched` or confidence cannot establish canonical relationships,
authorization or accounting completeness. Related IDs must not disclose hidden
Transactions. Target read/filter/write parity remains blocked on those decisions;
it must not disappear under the separate vendor-PDF import workflow.

The manually set `receiptEmailed` fact is separate from ingestion provenance.
Preserve it through the ordinary Transaction workflow, with one canonical field;
the source `hasEmailReceipt` alias is compatibility evidence, not a second value.

### Historical Summary
The Review tab surfaces work needing attention. The older proposal below asks
for richer context and grouping, but its flat-list diagnosis is obsolete and
its ProtoItem model is superseded. The Target Review Contract takes precedence.

The earlier proposal treated ProtoItem capture as recurring review work. That
model is superseded by real Items and Link; only legacy import reconciliation
retains source capture evidence. See [proto-item-capture.md](proto-item-capture.md).

## Current Behavior (What Exists Today)

- `ReviewCalculations.pendingTransactions` selects non-canceled Transactions
  whose source `isComplete` is not true.
- Horizontal Unassigned, Inventory and active-Project buckets show counts.
  Source Inventory versus Unassigned uses empty `itemIds`, not approved target
  ownership evidence; archived Projects are not bucket tabs.
- The selected bucket supports local Transaction search and the eight sort
  choices above. Cards open Transaction detail, not a generic proto resolver.
- The source conflates empty-bucket and query-no-match copy; the target must
  distinguish them and must not claim globally caught up from incomplete data.

## What's Changing

**Superseded/source-era proposal:** This section and all remaining proposal,
How It Works, Open Questions and Implementation Notes sections are historical
design evidence, not target instructions. In particular, their proto conversion,
generic assignment/`sell_items`, grouping and tappable-breadcrumb prescriptions
are not approved. The Target Review Contract and O-063 govern the redesign.

### Staying the Same
- The Needs Review tab still surfaces items that need attention — the core concept of a review queue is correct
- Items still open to their detail view when tapped

### Changing
- **Flat list → grouped by project.** The Needs Review list is reorganized into visual sections, one per project, so the user can immediately see which project each batch of items belongs to. Each section header shows the project name (and ideally the client name).
- **Context-free item detail → breadcrumb trail.** When the user taps into a needs-review item, the detail view shows a navigable breadcrumb path above the item content. The breadcrumb shows the item's full location: **Client > Project > Category** (e.g., "Smith Residence > Living Room Redesign > Furnishings"). Each segment of the breadcrumb is tappable, navigating the user up to that level.

### Adding
- **Project-grouped list layout** on the Needs Review tab with visual dividers between project sections
- **Inventory / Unassigned section** — items that are in inventory (not yet sold to a project) or that have no project association get their own section, visually distinct from the project groups. This makes it immediately obvious which items are floating and may need to be assigned.
- **Proto item sections** — unconverted Item Quick Drafts are shown alongside incomplete items/transactions, grouped by project, intended project, inventory/unassigned, or authoritative linked transaction. These rows point to the same drafts users can also find under the relevant Items surface.
- **Proto item conversion actions** — convert to item, merge with existing item, convert from inventory, or delete.
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
Item Quick Drafts render as capture groups rather than normal item rows. The row should emphasize user notes, photos, capture context, the **From Inventory** marker when enabled, and the next action. An item quick draft row does not open the normal item detail view because it is not an item yet; it opens a conversion workflow.

Needs Review uses the same unconverted Item Quick Drafts that appear under Project Items, Inventory Items, and Transaction Detail. Converting or deleting a draft from Needs Review removes it from both the global queue and its contextual Item Quick Drafts section.

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
