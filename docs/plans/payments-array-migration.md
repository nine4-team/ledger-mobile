# Payments Array — Migration Plan

**Spec:** [../specs/payments.md](../specs/payments.md)

Phased migration from `Transaction.paymentMethod: string` to `Transaction.payments: Payment[]`. Every phase is independently shippable, additive, and revertible. The single live user (1584) sees no broken screens at any point.

## Goals

- **No user-visible breakage at any phase.** The one production user is in the app daily.
- **Additive first.** New field added alongside the old one. Old code keeps working unchanged until each reader is converted explicitly.
- **No long-running dual-write divergence.** A read-time resolver synthesizes `payments` from `paymentMethod` when only the legacy field is set, so all readers can move to the new field before any data is migrated.
- **Each phase independently shippable and revertible.**

## Status

| Phase | Status |
|---|---|
| Phase 1 — add `payments` field + resolver (code only, no writes) | ⚪ Not started |
| Phase 2 — dual-write on transaction create/edit | ⚪ Not started |
| Phase 3 — convert readers (display, reports, search, exports) | ⚪ Not started |
| Phase 4 — backfill historical data | ⚪ Not started |
| Phase 5 — edit UI for split payments | ⚪ Not started |
| Phase 6 — retire `paymentMethod` direct reads/writes | ⚪ Not started |

## Phase 1 — Add the field and the resolver. No data changes.

**Scope:** introduce the type, the field, and a read-time resolver. Nothing reads from it yet. Nothing writes to it yet.

1. Add `Payment` type to the shared model (Swift + TypeScript MCP).
2. Add `payments: Payment[]?` to the Transaction model. Nullable. No validation yet.
3. Add a resolver: `resolvePayments(transaction) -> Payment[]`. Rules:
   - If `transaction.payments` is set and non-empty, return it.
   - Else if `transaction.paymentMethod` is set, return `[{method: paymentMethod, amountCents: amountCents}]` (a virtual one-entry list).
   - Else return `[]`.
4. Add a write-side validator that rejects writes where `payments` is set and `sum(amountCents) != transaction.amountCents`. Off by default; flip on at Phase 2.

**Ship gate:** iOS + MCP + Functions all build clean. App behaves identically to before — nothing is reading `payments` yet.

**Rollback:** delete the type and field; no data was written.

## Phase 2 — Dual-write on transaction create and edit.

**Scope:** every code path that writes a transaction now writes both `paymentMethod` and `payments`. Readers still use `paymentMethod`.

1. **Create paths** — every place that creates a transaction:
   - Manual transaction-create flow (iOS form): writes `payments: [{method, amountCents}]` (one entry).
   - `create_transaction` MCP tool: same.
   - Email ingestion pipeline (when it lands): writes the real array (multiple entries for split payments).
   - `sell_items`, `return_items`, etc.: write `payments` based on whatever they currently put in `paymentMethod`. For inventory-only operations with no money movement, leave both null.
2. **Edit paths**: the iOS edit form continues to edit `paymentMethod` as a single string, but the write also updates `payments` to a one-entry list reflecting the new method.
3. **Validator on.** Reject writes where the sum invariant fails.

**Ship gate:** new transactions created in iOS and via MCP have both fields. Existing transactions still have only `paymentMethod`. Resolver handles both.

**Rollback:** turn dual-write off, switch to writing only `paymentMethod`. Data already written to `payments` is harmless because nothing reads it.

## Phase 3 — Convert readers, one site at a time.

**Scope:** swap each read site from `transaction.paymentMethod` to `resolvePayments(transaction)`. Because the resolver synthesizes a one-entry list from the legacy field, no data migration is needed first. Each conversion is independent.

Order (least-risky first):

1. Transaction list row (display only).
2. Transaction detail view.
3. Reports (invoice, client summary, property management).
4. Search / filter (project-matching helper used by email pipeline; receipt-image OCR fallback path if any).
5. Exports (CSV / Excel / PDF).
6. Edit form display (form still writes `paymentMethod` — see Phase 5 for the input side).

After each site converts, single-payment transactions render exactly as before. Split-payment transactions (none in production yet) would render with all methods, but in practice this only starts mattering once the email pipeline begins writing splits in Phase 5+.

**Ship gate per site:** the converted screen looks identical to before on existing data. Verified visually and via the Phase-3 verification checklist (below).

**Rollback per site:** revert the read site to `transaction.paymentMethod`.

### Phase 3 verification checklist (run on 1584 after each site converts)

- [ ] Recent transactions list — payment method strings unchanged from pre-Phase-3.
- [ ] Transaction detail — payment method unchanged.
- [ ] A representative invoice — payment method column unchanged.
- [ ] Project budget tab — totals unchanged (Phase 3 should not touch budget math, but verify).
- [ ] Search by card last-4 in project notes — still finds the same transactions.

## Phase 4 — Backfill historical data.

**Scope:** populate `payments` on every existing transaction by reading `paymentMethod` and writing the equivalent one-entry list. Nothing functionally changes; the resolver was already returning the same shape virtually.

1. **Pre-backfill export.** Full Firestore export to `gs://ledger-nine4-backups/pre-payments-{date}/`. Same pattern as the taxonomy migration.
2. **Backfill script.** For each transaction with `paymentMethod` set and `payments` unset, write `payments: [{method: paymentMethod, amountCents: amountCents}]`. Idempotent — safe to re-run.
3. **Run on 1584 first.** Verify against the Phase-4 verification checklist below. Other production accounts (Ben's Biz, Assiist Biz, Ben's Bonks) follow once 1584 is green.
4. After backfill, the resolver's `paymentMethod` fallback is dead code on backfilled accounts but stays in place for safety.

**Ship gate:** every transaction with money has `payments` populated. Spot-check 20 transactions.

**Rollback:** the export. The migration is purely additive (adds `payments` without touching `paymentMethod`), so rollback is "ignore the new field" — but the export exists if needed.

### Phase 4 verification checklist

- [ ] Random sample of 20 transactions across vendors — `payments` populated, sum equals `amountCents`.
- [ ] Recent month of transactions in iOS list — display unchanged.
- [ ] Reports unchanged.

## Phase 5 — Edit UI for split payments.

**Scope:** the iOS transaction-edit form learns to display and edit a `payments` array. Until this ships, splits can be created by the email pipeline (Phase 2 dual-write) but only viewed, not edited, in the app. The edit form continues to round-trip a single payment as a single-entry list with no UI change for the common case.

1. Detail view: when `payments.length > 1`, show the per-method breakdown (read-only first).
2. Edit form: add the ability to add/remove payment rows, with sum-validation.
3. Single-payment transactions still render as one row by default — power users see the "+ add payment" affordance only when they need it.

**Ship gate:** create a test split-payment transaction in iOS, edit it, verify the sum constraint, save, reload, verify it round-trips.

**Rollback:** revert the form to single-payment-only. Existing split-payment transactions still render correctly in the detail view (read-only).

## Phase 6 — Retire `paymentMethod` direct writes.

**Scope:** stop writing `paymentMethod` directly. Treat it as a derived/legacy field. Possibly remove it later — but don't have to.

1. Write paths set only `payments`. The resolver / a denormalizer optionally keeps `paymentMethod` populated as a flat summary string for backwards-compat read paths or for any external integration that hasn't been converted.
2. Eventually: drop `paymentMethod` from the data model entirely. This is optional and probably never strictly necessary.

**Ship gate:** new transactions don't write `paymentMethod` directly. Old read paths (if any remain unconverted) still work via the denormalized summary.

## Open questions

- **Should `paymentMethod` survive forever as a denormalized summary?** Probably yes — cheap, helps any external query path or backup that doesn't want to parse JSON.
- **Per-payment metadata (last-4, brand, expiration?)** Right now `method` is just a string. Adding structure (`brand: "Amex", last4: "2008"`) would help search and matching but expands the change surface. Defer.
- **Sum validation tolerance.** Should we allow off-by-one (rounding)? Recommend strict equality; receipts come out exact.
- **Are there any external consumers of `paymentMethod`?** (Reports exported to CSV, third-party integrations, etc.) Need to inventory before Phase 6.

## Risks

- **Sum invariant violations on legacy edits.** If someone edits `amountCents` without touching `payments`, the sum breaks. Mitigation: the iOS edit form, after Phase 5, edits both together. Until then, the dual-write helper recomputes the one-entry list on every write so this can't happen for single-payment edits.
- **Performance.** Adding a small array to every transaction document is negligible.
- **External tools.** Anything reading Firestore directly (analytics, ad-hoc scripts) needs to know about both fields during the transition. Document in this plan and the spec.
