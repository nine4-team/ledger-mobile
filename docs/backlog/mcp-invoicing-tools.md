# MCP Tools for Invoicing

**Status:** Roadmap
**Created:** 2026-04-20

## Summary

Add invoice-related tools to the Ledger MCP server. Today the MCP surface covers transactions, items, inventory movement, projects, spaces, accounts, and notes — but has **zero** invoice tools. Invoicing is iOS-only.

## Motivation

Once the billing-invoicing v2 redesign ships (see [../specs/billing-invoicing-v2.md](../specs/billing-invoicing-v2.md) and [../plans/billing-invoicing-v2-implementation.md](../plans/billing-invoicing-v2-implementation.md)), invoices become the single source of truth for "what has been billed" and "what has been paid." That makes them a natural MCP target for reporting, bulk operations, and cross-project queries.

## Likely Tools

- `list_invoices` — filter by project, status, date range.
- `get_invoice` — full document including signed lines.
- `create_invoice` — build a draft from a picked set of transaction/item ids.
- `mark_invoice_sent` / `mark_invoice_paid` / `void_invoice`.
- `billable_pool` — the To Invoice query for a project.

## Dependencies

Blocked on billing-invoicing v2 shipping. Tool shape depends on the finalized signed-line model.

## Out of Scope for v2

Flagged in the v2 implementation plan as deferred. Not blocking v2 delivery.
