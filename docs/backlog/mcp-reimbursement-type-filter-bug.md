# MCP `list_transactions` — `reimbursementType` filter misses null/missing values

**Status:** Bug
**Found:** 2026-04-20 (during Q2 audit for billing-invoicing-v2)

## Summary

The MCP `list_transactions` tool's `reimbursementType: 'none'` filter only matches transactions where the field is literally the string `"none"`. It does not match transactions where the field is `null` or missing.

In practice the vast majority of untagged transactions have `reimbursementType` either absent or `null` — not `"none"` — so the filter silently returns zero results and hides the real untagged pool.

## How it surfaced

During the Q2 audit (see [../plans/q2-audit/round-1-non-itemized.json](../plans/q2-audit/round-1-non-itemized.json)), querying each active project with `reimbursementType: 'none'` returned 0 for every project. Removing the filter and looking at raw results showed ~72 non-itemized transactions across three projects with `reimbursementType` as `null` or missing.

## Fix direction

The filter should treat `"none"`, `null`, and missing as equivalent for the purpose of "untagged." Either:

- Normalize on write so the field is always present with an explicit `"none"` value, and backfill existing rows, or
- Change the filter to match `null`/missing as well as the literal `"none"`.

The second is less invasive. The first is cleaner long-term.

## Not blocking

Billing-invoicing v2 doesn't depend on this — the v2 model derives direction from transaction shape (`purchasedBy`, `type`, category), not from `reimbursementType`. This is a standalone MCP correctness bug.
