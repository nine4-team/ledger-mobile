# Decision Packet — O-041 Vendor-Spend Report Semantics

Status: proposed; not product authority  
Decision: O-041  
Owners: Reporting, Transactions, Vendor Evidence, Inventory, Security

## Decision Requested

What does Ledger's “spending by vendor” report measure, and which canonical
events, signs, dates, scopes, credits and currencies contribute?

The shipped MCP tool sums raw noncanceled Firebase Transaction amounts grouped
by a mutable source/vendor string. That is not a dependable target definition:
it does not distinguish Purchase from Return, cash from non-cash vendor credit,
Inventory from Project scope, posted from draft evidence, or currencies.
O-035 governs Client Summary and cannot authorize this separate business report.

## Mutually Exclusive Options

1. **Gross business outflow.** Sum 1584-paid posted Purchases and Expenses by
   vendor. Returns and credits appear separately and never reduce the headline.
2. **Net business vendor cash movement.** Sum 1584-paid posted Purchases and
   Expenses less actual cash Returns received by 1584, grouped by vendor label
   and currency. Show non-cash vendor credits separately until applied or
   cash-refunded.
3. **Project procurement.** Attribute Client- and 1584-paid procurement to a
   Project/vendor independent of which party paid, with payer-specific fields.
4. **Acquisition basis.** Attribute merchandise or landed acquisition basis to
   vendors even when payment timing, payer, scope or credit settlement differs.
5. **Retire the report.** Keep only canonical Transaction search/export and do
   not expose a vendor aggregate.

## Recommended Option

Choose option 2: a versioned **Business Vendor Cash Movement** report, with
1584-paid gross Purchases and Expenses, cash Returns received by 1584, net cash
movement and open/applied vendor credit shown as separate fields. Never combine
currencies, count Client money as 1584 cash, or silently treat non-cash credit
as received money.

This matches the confirmed Purchase/Return taxonomy, preserves O-028's
distinction between actual cash and vendor credit, and makes the report useful
without pretending cash movement is Item cost basis. If users need acquisition
basis later, add a separately named report rather than changing this one.

## Exact Proposed Semantics

- Include authoritative posted Inventory Purchases paid by 1584, 1584-paid
  Project Expenses, and actual cash Inventory Returns received by 1584 whose
  preserved vendor/source label is visible to the caller. A Project identifier
  on an Expense or later vendor-credit/refund record is contextual attribution;
  it does not turn that record into a Project-scoped Transaction.
- A 1584-paid Purchase or Expense contributes positive cents; an actual cash
  Return received by 1584 contributes negative cents. Client-paid Project
  Purchases, Client payments/refunds, Invoice collection Purchases, Transfers,
  Fees, capture drafts and quarantined source evidence contribute zero.
- Vendor cancellation, courtesy credit and unapplied credit do not alter cash
  movement. They appear in separate open/applied/cash-refunded credit fields
  under the eventual O-028 representation.
- Group by the exact vendor/source label snapshot preserved on the canonical
  money event. `VendorSuggestionID` remains entry/reference convenience and is
  never promoted to canonical Vendor or historical accounting identity. Distinct
  label snapshots remain distinct unless a later explicit Vendor identity/alias
  decision authorizes a merge; do not fabricate or auto-merge identity.
- Partition every result by currency. No conversion or mixed-currency total is
  implied.
- Filter and order by authoritative posting/effective event time, with the
  heterogeneous `(event kind, stable record ID)` pair as the tie-breaker.
  Created/updated timestamps are evidence, not the reporting basis.
- Every included Purchase/Return Transaction remains in an Inventory/1584-owned
  scope. A Project-scoped Return is Client money under D-002/D-007 and therefore
  contributes zero to this report. An optional Project filter selects only
  contextual attribution on 1584-paid Expenses and any later 1584-owned
  credit/refund record that O-028 explicitly allows to carry that context; an
  Inventory filter selects Inventory-owned Purchases/Returns. Neither filter
  changes payer/recipient perspective. Account-wide totals combine only
  authorized visible business-owned events and carry completeness/readiness
  versions.
- Reversals/corrections use their canonical supersession/void semantics; old
  rows remain auditable but do not double count.

## Affected Surfaces

- `MCPTOOL-556E4BBD4A8C` (`spending_by_vendor`)
- `MCPMOD-917C20FEDA6A` (analytics module)
- `QUERY-AD2810269F0F` (optional Project filter in the current tool)
- reporting/search/export capability dossier and future report/query contracts
- Transaction, vendor-credit, migration and reconciliation projections consumed
  by the report

## Confirmed Constraints This Cannot Reopen

- D-001/D-007: only Purchase, Return and Transfer are target Transaction types;
  Return means actual money received by the reporting scope.
- D-002: money meaning is scope-relative.
- D-003–D-006: Client identity and same-Client Transfers are separate from
  vendor aggregation.
- D-017: Transfers are client-wide net zero and never vendor spend.
- O-028 remains the authority for non-cash vendor adjustment/credit behavior.
- O-029/O-032 remain the authority for posting, void/correction and incomplete
  source Transaction handling.
- O-031 remains the authority for Item tax/acquisition basis; this decision does
  not define landed cost.

## Domain and Query Consequences

The target needs one named query such as `VendorCashMovementQuery`, returning a
versioned page/snapshot with Account, optional Inventory ownership scope or
Project contextual attribution, exact
vendor-label snapshot bucket, currency, gross 1584 Purchase cents, gross 1584
Expense cents, cash Return-to-1584 cents, net business cash movement cents,
separate vendor-credit fields, stable `(event kind, record ID)` cursor,
readiness and accounting-authority version.

The app and MCP must consume the same projection. Neither may re-sum raw local
arrays or accept arbitrary field/grouping names.

## Schema and Projection Consequences

- No raw Firebase Transaction shape becomes target schema authority.
- The report projects canonical posted Transaction facts, exact vendor-label
  snapshots and vendor-credit facts; it does not own them or create Vendor
  identity.
- A materialized projection is optional and must be rebuildable, versioned and
  reconciled against canonical rows.
- Physical table/index choices remain deferred under A-003/A-004 until the
  vertical spike and the owning implementation slice authorize them.

## Authorization and Privacy

- Require active Account membership and financial visibility for every included
  scope before aggregation.
- Counts and totals must be computed after authorization so hidden vendor or
  Transaction existence cannot leak.
- Legacy vendor labels are financial data and follow the same visibility policy.
- Account-wide queries must not widen access beyond the union of authorized
  Project/Inventory scopes.

## Offline and Sync Consequences

- The app may show only locally authorized, readiness-labelled projection data.
- Partial local coverage must render incomplete/unavailable, never a plausible
  zero or final total.
- Offline filters and ordering must match the online/MCP contract.
- Reconnect, projection-version change and rejection must recompute without
  duplicate or stale contributions.

## Migration and Reconciliation

- Preserve every source Transaction/Expense ID, raw vendor/source label, type,
  amount, payer/recipient, scope, status, timestamps and correction evidence in
  protected migration correlation.
- Classify each source contribution as included 1584 Purchase, included 1584
  Expense, included cash Return to 1584, excluded Client/Invoice/non-cash/other,
  or quarantined ambiguous evidence.
- Reconcile per Account/business-owned scope/contextual Project
  attribution/vendor bucket/currency and report zero unexplained cent
  differences before cutover.
- Do not silently map current `source` strings or Vendor suggestions to stable
  Vendor identity.

## Required Tests

- 1584-paid Purchase/Expense positive sign; Return received by 1584 negative
  sign; exact net cents.
- Client-paid Purchase, Invoice collection, Transfer, Client payment/refund, Fee
  and drafts excluded.
- Vendor credit open/applied/cash-refunded states remain separate and conserved.
- Inventory ownership, Project contextual attribution and Account-wide
  isolation; Project-scoped Return exclusion; payer-perspective invariance and
  cross-account denial.
- Multi-currency partitioning with no implicit combined total.
- Exact vendor-label buckets, case/spelling variants and no implicit
  suggestion-based/rename/merge behavior.
- Posting/effective-date filter boundaries and stable heterogeneous
  `(event kind, record ID)` cursor tie-breaks.
- Correction, reversal, retry and projection rebuild without double count.
- Financial-visibility negative tests where hidden rows affect neither totals nor
  disclosed counts.
- Offline partial-readiness, restart, reconnect and app/MCP parity.
- Migration fixtures with raw legacy vendor strings and quarantined ambiguity;
  zero unexplained cent differences.

## Approval Checklist

- [ ] Choose gross business outflow, net business cash movement, Project
  procurement, acquisition basis, or retirement.
- [ ] Approve the 1584 payer/recipient perspective and treatment of Expenses,
  Client-paid Purchases and Invoice collection.
- [ ] Approve signs and included/excluded canonical event types.
- [ ] Approve vendor-credit presentation and O-028 dependency.
- [ ] Approve scope and posting/effective-date basis.
- [ ] Approve exact label-snapshot grouping or separately authorize a new
  canonical Vendor identity/alias model.
- [ ] Approve strict per-currency partitioning.
- [ ] Approve offline readiness and security behavior.
- [ ] Approve migration/reconciliation rules.

Approval closes only O-041. It does not close O-028, O-029, O-031, O-032,
A-003, A-004 or any production/cutover gate.
