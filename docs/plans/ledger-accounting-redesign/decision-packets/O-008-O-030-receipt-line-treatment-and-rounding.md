# Decision Packet — O-008/O-030 Receipt-Line Treatment and Rounding

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Receipt Evidence, Transaction Posting, Expenses, Item Basis, Migration
Unlocks: 19 unique residual surfaces (O-008: 11; O-030: 11; overlap: 3)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this combined contract:

> Keep every printed nonphysical receipt amount as exact signed source evidence,
> then require explicit treatment allocations that sum to that line: allocate it
> to Item acquisition basis, create Project Expense demand, classify it as
> Business-absorbed/nonbillable, or retain it as evidence-only where the owning
> scope already accounts for the money. A line may be split across treatments in
> exact cents. No description (“tax,” “shipping,” “discount,” etc.) silently
> chooses treatment. Receipt reconstruction and billability readiness are
> separate.

> Canonical arithmetic always balances exactly. If the source receipt itself is
> off by one cent, add an explicit visible one-cent `source_rounding` line when
> the source identifies rounding, otherwise an explicit
> `unexplained_source_variance` line requiring review. Never use a tolerance to
> call an unequal record complete and never relabel the cent as tax/discount.

O-008 and O-030 close together because a tolerated cent has no source identity
and therefore cannot receive an honest billable/absorbed/basis treatment.

## Confirmed Constraints

- Physical Items plus signed `NonItemReceiptLine` evidence reconstruct the final
  Purchase/Return amount; fake Items are prohibited.
- `amountCents` is final actual money. Tax/subtotal/rate inference is not receipt
  completeness authority.
- Transaction type remains Purchase/Return/Transfer; receipt lines add no type.
- Direct Client-paid Project money is already paid Project activity. Business-
  paid Project costs become Expenses/Item demand only through the approved
  Invoicing model.
- One source amount cannot contribute to Item basis, Expense demand and budget
  more than once.
- O-031 governs exact per-Item basis allocation mechanics. This packet chooses
  whether and how much of a source line enters that allocation pool.
- Whole-Invoice collection freezes source/category allocations and moves them
  unpaid to paid without changing recognized value.

## Options

### Option A — Infer treatment from source description/type

Recommendation: reject. Shipping may be billable, included in Item basis or
absorbed; discounts may reduce different bases; tax treatment varies by Item and
scope. Text heuristics may suggest but cannot authorize accounting.

### Option B — One treatment per entire line

Recommendation: reject as the canonical model. A shipping/tax/discount line can
legitimately be split across Items, Projects or absorbed amounts. Forcing a
single treatment creates fake lines or silent cents.

### Option C — Exact treatment allocations (recommended)

Keep source line immutable and assign one or more typed exact-cent treatments
whose signed total equals the line.

## Source Evidence Versus Treatment

`NonItemReceiptLine` remains source evidence:

- stable ID and source order;
- source description and optional quantity;
- positive magnitude plus increase/decrease effect;
- signed cents derived from effect;
- source/import evidence and revision; and
- optional classification suggestions with confidence, never authority.

Treatment rows answer what Ledger should do with those cents. Every signed line
must be fully assigned before treatment readiness is complete:

| Treatment | Meaning and downstream effect |
|---|---|
| `item_acquisition_basis` | Adds/reduces an approved Item acquisition component pool; exact Item allocation follows O-031 |
| `project_expense` | Creates or joins a typed signed Project Expense source because 1584 paid and intends to charge/credit the Client |
| `business_absorbed` | 1584 bears the amount; no Client demand/budget contribution is created |
| `scope_money_evidence` | The scope owner's canonical Purchase/Return already includes the amount; retain category/component evidence without creating Invoicing demand |
| `evidence_only_review` | Amount is retained and exact receipt arithmetic is possible, but business treatment remains unresolved and downstream billable/basis actions stay blocked |

Treatments use signed cents. Their sum for a source line must equal the line's
signed cents exactly. A decrease allocated to basis/Expense reduces that exact
pool; it is not stored as a negative magnitude pretending to be an increase.

`evidence_only_review` is not a way to mark treatment complete. It lets actual
money evidence be posted when O-032's posting profile is satisfied while keeping
billability/basis readiness explicitly incomplete. Whether a story permits that
separation is part of its posting evidence profile.

## Scope and Payer Rules

### Client-paid Project Purchase/Return

The Client already paid or received money. Receipt lines are
`scope_money_evidence` with explicit Project category/component allocations.
They create no Expense or Invoice source. Item acquisition-basis allocation may
also be recorded where the Client owns the Item, but budget contribution remains
the one direct money record/allocation.

### Business Inventory Purchase/Return

1584 paid/received money. Lines may enter Inventory Item acquisition basis or be
Business-absorbed. They create Project Expense demand only when an explicit,
authorized Project relationship and billable intent exists. A Project link never
changes the Inventory Transaction's scope owner.

### 1584-paid Project cost

The reviewed source is an Expense, not a Project Purchase. Its receipt line
treatments define billable signed Expense components versus Business-absorbed
components. Physical goods still route through Item acquisition/occurrence rules.

One allocation may not simultaneously be `item_acquisition_basis` and
`project_expense`. If product pricing bills the Client for an Item, that billing
uses the explicit Item occurrence price, not a duplicate Expense generated from
the same allocated receipt cent.

## Treatment Workflow

1. Capture/import immutable source Item and non-Item lines.
2. Reconstruct exact final money independently of treatment.
3. Show suggested line treatments separately from confirmed values.
4. User/authorized automation submits exact treatment allocations with source,
   eligible Item/Project and revision hashes.
5. The handler validates scope/payer/category, prevents duplicate economic
   identity, writes the complete allocation set and any Expense/basis links
   atomically, and returns readiness.
6. Later correction appends a superseding allocation set. It cannot rewrite paid
   Invoice or collected Item history.

Bulk “apply to all” is allowed only as a preview/confirmation over exact stable
line IDs and cents. App and MCP use the same treatment taxonomy and handler.

## One-Cent Source Variance

Canonical completeness has no tolerance:

```text
sum(physical Item source cents)
+ sum(signed non-Item source-line cents)
= final Transaction amount cents
```

When the original receipt arithmetic differs by exactly one cent:

- if the receipt explicitly labels rounding, create a stable
  `source_rounding` increase/decrease line preserving that wording/evidence;
- otherwise, after explicit review, create a stable
  `unexplained_source_variance` line of exactly one cent with source amounts,
  actor, reason and review state;
- display the line in receipt audit, MCP, migration and correction history;
- default its treatment to `business_absorbed` for Business-paid evidence or
  `scope_money_evidence` for direct Client-paid money, unless an authorized
  explicit correction chooses another legal treatment; and
- never infer tax, discount, shipping, Item price or category from the residual.

Variance magnitude greater than one cent blocks canonical posting/import until
source evidence is corrected or explicitly quarantined. More than one variance
line for one source Transaction is invalid. Removing/correcting it must restore
exact equality.

This preserves the accepted “at most one cent” product tolerance as explicit
data, not an arithmetic loophole. Every canonical record still balances exactly.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| receipt Item/non-Item components | Immutable ordered exact source evidence and signed cents |
| `receipt_treatment_sets` | Complete/superseded allocation revision, source hash, actor, readiness |
| `receipt_line_treatments` | Exact signed cents, treatment kind, Project/Expense/basis/category correlation |
| Expense component links | Stable economic identity from treated source cents into open Project demand |
| acquisition component pools | Stable source cents eligible for O-031 Item allocation |
| source rounding/variance lines | Explicit one-cent source evidence and review provenance |
| contribution/correlation rows | One source allocation contributes through exactly one paid/unpaid authority |
| operation/results | Idempotency, payload hash, expected revisions and typed outcome |

Use stable IDs, `bigint` cents, explicit currency/effect/treatment checks and
foreign keys. Enforce exact line-treatment totals and one active treatment set in
the trusted transaction; use deferred constraints or handler validation plus
reconciliation where a cross-row sum cannot be a simple check. Index every
foreign key/RLS key, source line/treatment revision, open review queue and
Project/Expense/basis correlation. Avoid JSON for core allocation relationships.

## Authorization, RLS, Sync, and Offline

- Receipt amounts, treatments, basis and Expense links are financial data.
  RLS/Sync requires active Account membership, source/Project access and exact
  financial/category capabilities. Restricted users cannot infer hidden line or
  treatment counts/totals.
- Direct writes to treatment/basis/Expense/contribution authority are revoked.
  Trusted handlers validate existing/resulting Account scope and source cents.
- Selected Project/Inventory streams include authorized receipt/treatment
  summaries and readiness needed for active work. Detailed receipt evidence may
  use a bounded on-demand stream without falsely claiming completeness.
- Offline treatment edits are durable operations bound to exact source and
  eligible-target revisions. Pending previews are marked pending; accepted basis,
  Expense and budget projections do not change optimistically before the trusted
  result where A-015 requires the spike.
- Concurrent source edit, treatment, Item allocation, Expense Invoice membership,
  posting, collection or correction returns a typed conflict or serial result;
  no partial/double contribution is allowed.

## Migration and Reconciliation

- Preserve raw amount/subtotal/rate/discount, Item membership/prices, receipt
  descriptions/order/effects, final amount, source images and audit fields from
  the immutable Firebase export.
- Convert explicit tax/shipping/warranty/discount/etc. evidence into stable
  non-Item source lines without treating description as billability authority.
- Preserve legacy Transaction `discount` as one or more decrease lines with
  deterministic IDs and source correlation.
- Accept a deterministic one-cent variance line only when reconstructed source
  evidence differs from final amount by exactly one cent; classify explicit
  source rounding separately from unexplained variance. Larger differences
  quarantine.
- Map treatment only where payer/scope/Project/category/basis intent is proven.
  Otherwise retain `evidence_only_review`; never fabricate Expense demand or
  spread tax across Items during migration.

Reconcile final cents, every source line ID/order/effect, treatment-set exact
sums, basis/Expense links, one-cent variance reason, economic contribution
identity, readiness and all quarantine reasons. Repeat/interrupted import must
produce identical IDs and allocations.

## Required Acceptance Tests

- shipping/tax/warranty/discount fixtures each support basis, Expense, absorbed
  and unresolved treatments without description-driven automatic authority;
- split treatment sums exact signed cents and rejects missing/duplicate/over-
  allocated cents;
- the same source cent cannot contribute through both Item occurrence/Expense or
  direct Purchase/Invoice paths;
- direct Client-paid and Business-paid scopes create the correct money/demand
  boundaries;
- explicit source rounding and unexplained one-cent variance balance exactly,
  stay visible and never become inferred tax/discount;
- zero and greater-than-one-cent unexplained variance rules fail correctly;
- stale source/eligible Item/Project/category revisions write no partial set;
- O-031 deterministic Item allocation consumes only approved basis pools;
- restricted users cannot read or infer protected lines/treatments/results;
- offline review/restart/reconnect is idempotent and visibly pending; and
- migration fixtures preserve every cent/line/disposition with zero unexplained
  source-to-target differences.

## Approval Consequences

If approved:

1. update canonical NonItemReceiptLine, Transaction, Expense, Item basis and
   Invoicing specs and record confirmed decisions;
2. promote treatment/readiness/variance contracts into architecture 02/04/05/
   06/07 and the O-031 basis proposal;
3. remap the 19 affected surfaces while retaining O-006/O-015/O-031/O-032 and
   other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, exact-cent fixtures
   and migration mappings; and
5. include concurrent treatment/post/collection and one-cent migration cases in
   the target spike.

## Approval Checklist

- [ ] Source receipt evidence and business treatment are separate.
- [ ] Treatment allocations may split but must sum exact signed line cents.
- [ ] Basis, Project Expense, Business-absorbed and direct scope-money evidence
  are mutually non-duplicative outcomes.
- [ ] Description/type may suggest but never authorize treatment.
- [ ] Canonical completeness always balances exactly.
- [ ] A one-cent source discrepancy becomes an explicit visible rounding or
  unexplained-variance line, never hidden tolerance or inferred tax/discount.
- [ ] Larger unexplained differences block/quarantine.
