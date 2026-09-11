# Decision Packet — O-031 Item Tax and Acquisition Basis

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Item Accounting, Receipt Evidence, Inventory, Pricing, Migration
Unlocks: 16 residual surfaces; O-008/O-030 still govern which non-Item lines are
allocatable/billable and source rounding
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this model:

> Preserve the Item's source merchandise amount separately from acquisition
> allocations. Never derive or inherit a per-Item tax rate from a Transaction
> header. When source evidence or an explicit reviewed allocation assigns tax or
> another approved acquisition component to an Item, store exact integer cents,
> method, source and revision on the acquisition relationship. Derive the Item's
> landed acquisition basis from those exact components. Project billing price is
> a separate explicit amount and never silently inherits Transaction tax.

If an acquisition-level amount has not been allocated, basis readiness is
`partial`; the system does not treat missing allocation as zero. An explicit
user-confirmed deterministic allocation may distribute an approved pool, but an
automatic background trigger may not.

This proposal does not decide O-008's business treatment for shipping, warranty,
discount, tax, and similar receipt lines or O-030's one-cent source discrepancy.
It defines the representation and arithmetic after a component is classified.

## Confirmed Constraints

- Receipt reconstruction uses exact signed integer cents and stable source lines.
- A Transaction-level tax/non-Item line is not a fake Item.
- Mixed tax treatment and discounts cannot be inferred safely from a receipt
  total or one header rate.
- One physical Item identity may have multiple acquisition/sale/return/resale
  occurrences; historical bases belong to the relevant acquisition/occurrence,
  not a mutable polymorphic Item field.
- Business-paid Link may optionally reference a proven Inventory acquisition.
  It creates open Item demand, not a Project Transaction.
- Whole-Invoice collection freezes exact billed amounts. Later acquisition-basis
  correction cannot rewrite collected Client history.
- Purchases/Returns are actual money; changing an allocation is accounting
  correction evidence, not a physical movement.

## Options

### Option A — Copy the Transaction tax rate to every Item

Recommendation: reject. It fails for mixed taxable/nontaxable lines, receipt-
level discounts, jurisdiction rounding, quantity splits, and source receipts
whose tax is known only as total cents.

### Option B — Store only a tax-inclusive Item price

Recommendation: reject as the canonical evidence model. It is simple for UI but
cannot explain the merchandise/tax/discount components, reconcile source lines,
or correct one allocation without overwriting historical basis.

### Option C — Exact acquisition components plus derived landed basis
(recommended)

Store merchandise and each approved allocated component in cents with provenance.
Derive landed basis and expose an explicit readiness state.

Recommendation: approve. It is exact, auditable, compatible with mixed receipts,
and keeps Client billing independent from Business acquisition accounting.

## Monetary Model

For acquisition occurrence `a` and Item `i`:

```text
merchandise_cents(i, a)
  = exact Item merchandise line assigned to that acquisition

allocated_component_cents(i, a)
  = sum(exact signed allocations for tax/discount/shipping/etc. that O-008
        classifies as acquisition basis)

landed_basis_cents(i, a)
  = merchandise_cents(i, a) + allocated_component_cents(i, a)
```

The sum of all Item allocations for one source component must equal that source
component's exact signed cents or the allocation set is not complete. Negative
discount allocations reduce basis. Zero allocation rows are omitted.

These values remain distinct:

- merchandise amount: what the Item line itself cost;
- landed acquisition basis: merchandise plus approved allocated components;
- current proposed Project billing price: explicit editable open-demand amount;
- frozen billed/collected amount: immutable occurrence/Invoice allocation; and
- current replacement/market/display price, if the product later adds one.

No one value is a fallback alias for another without a named product rule.

## Allocation Evidence and Methods

Every acquisition component allocation records:

- Account, acquisition, Item, source component and allocation-set IDs;
- exact signed cents and currency;
- method: `source_exact`, `user_exact`, or `user_confirmed_proportional`;
- source evidence/revision and eligible Item set;
- actor, operation, effective time and expected revisions; and
- superseded/correction correlation where applicable.

`source_exact` is preferred when the receipt/vendor evidence identifies Item-
specific tax or another component. `user_exact` records a deliberate per-Item
entry. `user_confirmed_proportional` is allowed only after showing the exact
pool, eligible Items, basis used, resulting cents and rounding assignment.

The deterministic proportional method is:

1. allocate by nonnegative eligible merchandise cents;
2. compute floor cents from exact rational shares;
3. distribute remaining cents by descending fractional remainder;
4. break equal remainders by stable Item ID; and
5. persist the final exact cents, eligible-set hash and algorithm version.

It is never applied silently by a trigger, importer, app heuristic, MCP helper,
or migration script. Items explicitly known non-taxable/ineligible are excluded;
unknown eligibility blocks confirmation or remains partial rather than assumed.

A displayed effective tax percentage may be derived from exact cents for user
explanation. It is not persisted as the accounting authority or copied to later
Transactions/Items.

## Basis Readiness

Acquisition basis exposes:

- `complete`: every source component classified by O-008 and every basis-
  applicable component fully allocated or explicitly retained at Transaction
  level under the approved policy;
- `partial`: merchandise is known but one or more applicable component pools are
  unallocated/ambiguous;
- `not_applicable`: no Item acquisition basis belongs to this story; or
- `quarantined`: contradictory/missing source evidence prevents safe basis.

UI, MCP, reports and migration must show the state. `partial` is never rendered
as a complete landed basis of merchandise plus zero tax.

If a pricing action offers “use cost” or an automatic minimum, it may use landed
basis only when `complete`. Otherwise it must request an explicit billing price
or show the missing allocation; it cannot guess a Transaction rate. Ordinary
Project billing still uses the explicit Project price and can proceed under the
approved Link rules without fabricating acquisition evidence.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `item_acquisitions` | Item/acquisition identity, merchandise cents, currency, source and basis readiness |
| transaction receipt components | Exact source Item and non-Item line evidence that reconstructs final amount |
| `acquisition_allocation_sets` | Component, eligible-set hash, method/version, status, actor and revision |
| `acquisition_item_allocations` | Exact signed cents for one source component and Item acquisition |
| basis projection | Derived merchandise/allocated/landed cents and readiness; rebuildable, not a second writer |
| correction events | Append-only supersession/reallocation evidence |

Core rows use `bigint` cents, explicit currency, stable IDs, foreign keys and
checks. Enforce unique active allocation per `(allocation_set, item_acquisition)`
and exact allocation totals in the trusted command transaction. Index every
foreign key plus acquisition/Item history and source-component lookup. Use
partial indexes for active allocation sets and incomplete/quarantined review.

## Commands and Mutation Rules

- `AssignExactAcquisitionComponent` records source/user exact cents.
- `PreviewProportionalAcquisitionAllocation` is a deterministic query that
  returns eligible-set/revision/algorithm hashes; it grants no mutation authority.
- `ConfirmProportionalAcquisitionAllocation` revalidates and writes the complete
  set atomically using the confirmed plan.
- `CorrectAcquisitionAllocation` appends a superseding set and correction event;
  it never edits a collected Invoice amount or paid occurrence.
- `SetProjectBillingPrice` changes only eligible open billing demand and uses its
  own revision/paid-lock rules.

Posting locks the Transaction/receipt components, affected acquisitions/Items,
allocation set and operation in deterministic order, validates exact sums and
writes facts/result atomically. External receipt parsing/media work occurs before
the transaction. App and MCP call the same handlers.

## Authorization, RLS, Sync, and Offline

- Acquisition cost, tax and allocation details are financial data. RLS/Sync
  requires active membership plus the applicable financial capability; physical
  Item visibility alone does not expose basis or even hidden allocation counts.
- Direct writes to allocation/basis/correction rows are revoked. Trusted handlers
  validate Account/scope/source/Item/category and both existing/resulting rows.
- Selected Inventory/Project streams include authorized basis summary/readiness
  needed for the current workflow. Full receipt/allocation history may be a
  bounded on-demand stream with explicit completeness.
- Offline exact entry or confirmed allocation is a durable operation with the
  exact source/eligible-set revisions. Optimistic UI is pending; authoritative
  basis remains the last accepted version until reconnect.
- Concurrent source correction, Item membership change, allocation confirmation,
  Link, movement, Invoice collection or correction produces a typed conflict and
  no partial allocation.

## Migration and Reconciliation

For each Firebase Transaction/Item relationship:

1. preserve raw Item price, tax rate/amount if present, Transaction tax/subtotal/
   discount, receipt lines, quantity, membership/back-reference, snapshots and
   source revision;
2. reconstruct exact merchandise only where source evidence supports the Item/
   acquisition relationship;
3. import per-Item tax/allocation as `source_exact` only when exact cents and
   eligible identity are proven—not from a shared header rate alone;
4. retain ambiguous inherited rates, mixed treatment and arithmetic residual as
   protected migration evidence with `partial`/`quarantined` reasons;
5. never distribute a source pool during migration without an approved,
   versioned policy and reviewed fixture outcome; and
6. preserve paid Invoice/occurrence amounts separately from any corrected
   acquisition basis.

Reconcile Transaction final cents, receipt components, merchandise cents,
allocation pools/item sums, basis readiness, source rates retained as evidence,
Item/acquisition identities, correction chains and frozen paid amounts. Every
source tax field must map to exact authority, protected evidence, quarantine or
approved omission.

## Required Acceptance Tests

- mixed taxable/nontaxable Items never receive a copied header rate;
- source-exact and user-exact allocations reconstruct every pool cent exactly;
- deterministic proportional fixtures cover equal remainders, one-cent pools,
  discounts, zero merchandise, quantity, stable-ID tie breaks and retry;
- same operation/payload returns one set; stale eligible-set/source revision
  writes nothing;
- `partial` never displays or exports missing allocations as zero/complete;
- “use cost” refuses incomplete basis while explicit Project billing price stays
  independent;
- correction supersedes allocation evidence without changing frozen collected
  Invoice/occurrence amounts;
- restricted users cannot read or infer basis/allocation/source counts through
  RLS, Sync, search, reports, errors or operation results;
- offline confirm/restart/reconnect converges without duplicate cents;
- app/MCP use identical arithmetic and validation fixtures; and
- migration never turns a legacy Transaction rate into per-Item authority
  without exact supporting evidence.

## Approval Consequences

If approved:

1. update canonical receipt/Item/inventory/pricing specs and record the confirmed
   decision;
2. promote the acquisition component/readiness model into architecture 02/04/05/
   06/07 and the O-007/O-015 relationship model;
3. remap the 16 O-031 surfaces while retaining O-008/O-030/O-032 and other
   independent blockers;
4. specify exact allocation fixtures, reviewed conceptual constraints/indexes,
   RLS/Sync projections and migration rules; and
5. include offline conflict, exact-cent allocation and restricted-data leakage
   cases in the target spike.

## Approval Checklist

- [ ] Merchandise, allocated components, landed basis and Project billing price
  are separate values.
- [ ] No Transaction header tax rate is inherited as per-Item authority.
- [ ] Allocation stores exact cents, method, source, revision and actor.
- [ ] Proportional allocation is deterministic and requires explicit confirmation.
- [ ] Missing applicable allocation produces `partial`, never implicit zero.
- [ ] Paid/collected billing history does not change when acquisition basis is
  corrected.
- [ ] O-008 and O-030 remain open for line treatment and source rounding.
