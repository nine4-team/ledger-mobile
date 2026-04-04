# Search Results & Item Detail — Contextual Details
Status: modify
Last updated: 2026-04-02

## Summary
When searching for items across the app, the user needs enough context to identify which item they're looking at — specifically, which project it belongs to. The full mapping details (location, transaction, purchaser, etc.) should be accessible when the user clicks into the item detail view, not necessarily crammed into the search result row itself.

## Scope
- Applies to the **designated search page** and **item detail view** across the app
- Applies to **all platforms** unless noted otherwise [needs confirmation]

## How It Should Work

### Search Result Row
Each search result should show enough context to differentiate items at a glance. The key addition is the **project name** — so the user can tell which client's project the item belongs to.

- **Item name and basic info**: [exact fields currently shown TBD via discovery]
- **Project name**: Which project the item is in (e.g., "Smith Residence"). This is the critical missing piece — especially when "purchased by client," the user needs to see *which* client's project to know who.
- **Purchaser label**: Can remain as "Client" or "Business" — no need to show the specific client's name as long as the project name is visible

The search result row does **not** need to show every detail. It just needs enough for the user to say "that's the one" and click in.

### Item Detail View (click into an item)
When the user taps/clicks on an item from search results (or anywhere in the app), the item detail view should show the full mapping and context:

- **Project**: Which project the item belongs to
- **Space**: Which space the item is in (if applicable)
- **Inventory/Account**: Which inventory or account it's associated with
- **Transaction**: Which transaction the item is tied to (reference/number, date, or identifier)
- **Purchaser**: "Client" or "Business"
- **Any other location/relationship details** that help the user understand where this item sits in the system

The goal: the user should be able to open any item and see the complete picture of where it lives and what it's connected to, all in one place.

## What's Changing

### Staying the Same
- The search input and query behavior
- The purchaser label format ("Client" or "Business" is fine as-is)
- The existence of the search page and item detail view

### Changing
- **Search result rows**: Add the project name so the user can see which client's project an item belongs to
- **Item detail view**: Ensure all mapping/location details are present and visible (project, space, inventory, transaction, purchaser)

### Adding
- **Project name on search results**: visible in the result row
- **Full mapping section on item detail**: all location and relationship info consolidated in one view

### Removing
- Nothing removed

## Open Questions
- What fields are currently shown per search result row? [needs discovery]
- What fields are currently shown on the item detail view? Some of this mapping info may already be there. [needs discovery]
- Can an item belong to multiple projects or spaces simultaneously? If so, how should that be displayed?
- Does the search page also return transactions as results (not just items)? If so, do transaction results also need the project name?
