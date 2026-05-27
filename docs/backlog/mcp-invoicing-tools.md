# MCP Tools for Invoicing

**Status:** Implemented in local MCP server; needs connector smoke test against a sandbox account
**Created:** 2026-04-20
**Updated:** 2026-05-26

## Summary

Add invoice-related tools to the Ledger MCP server so agents can work with invoice demands without creating fake transaction records.

## Motivation

The active billing model (see [../specs/billing-invoicing.md](../specs/billing-invoicing.md)) separates demand from money movement:

- Invoices demand money.
- Invoice lines describe the components of that demand.
- Transactions record money that actually moved.
- Some transactions are linked back to invoices as settlement evidence.

That makes invoices a natural MCP target for reporting, contract import, bulk operations, and cross-project settlement queries.

## Implemented Tools

- `list_invoices` — filter by project, status, date range.
- `get_invoice` — full document including signed lines.
- `create_invoice` — build a draft from picked item ids, transaction ids, and manual New Charge lines.
- `add_invoice_line` / `update_invoice_line` — add or edit item, transaction, or manual lines on a draft invoice.
- `mark_invoice_sent` / `void_invoice`.
- `billable_pool` — the To Invoice query for a project.
- `mark_invoice_collected` — create one settlement transaction for the invoice.
- `mark_invoice_lines_collected` — create one settlement transaction for selected lines.
- `apply_contract_setup` — accepts contract-derived structured fields, updates/creates a project, and creates draft manual New Charge lines.

## Follow-Ups

- Add sandbox MCP tests around the implemented tools.
- Add a dedicated existing-transaction settlement-linking workflow if real users need to match bank-feed payments after the fact.

## Dependencies

Depends on the canonical billing-invoicing model, especially stable invoice-line IDs and settlement linkage fields on transactions.

## Out of Scope for v2

Payment processing remains out of scope. MCP tools create/link Ledger records; they do not move money through Stripe, Square, QuickBooks, or a bank.
