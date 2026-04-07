# Project List — Bugs
Status: modify
Last updated: 2026-04-05

## Summary

Bug reports and fixes related to the Projects list screen — the main screen users see showing their active and archived projects, plus the Business Inventory section.

## Bug: Business Inventory Shows "0 items · 0 transactions"

**Severity:** High (user-facing, undermines confidence in data integrity)
**Reported:** 2026-04-05
**Location:** Projects screen → Business Inventory card

### Current Behavior (Bug)

The Business Inventory card on the Projects screen displays "0 items · 0 transactions" as its subtitle, regardless of how many items and transactions actually exist in the inventory. When the user taps into Business Inventory, the items and transactions are all there — the data is fine, only the count displayed on the card is wrong.

### Desired Behavior

The Business Inventory card should display accurate counts reflecting the actual number of items and transactions in the inventory. For example, if the inventory contains 47 items and 112 transactions, the card should read "47 items · 112 transactions".

### Why This Matters

A designer who has spent time entering inventory sees "0 items · 0 transactions" on the main Projects screen and immediately worries their data is gone. Even if they tap in and see everything is fine, that moment of alarm erodes trust in the app. The counts are one of the first things a user sees — they need to be accurate.

### What's Changing

- **Staying the same**: The card layout, the inventory icon, the "Business Inventory" title, and the tap-to-enter behavior all stay as-is
- **Changing**: The subtitle counts ("0 items · 0 transactions") → real-time accurate counts pulled from actual inventory data

## Open Questions

- Is this a data fetching issue (the count query isn't running or is running with wrong parameters)?
- Is the count cached somewhere and not invalidating when items/transactions are added?
- Does this only affect Business Inventory, or could project cards also show stale counts?
