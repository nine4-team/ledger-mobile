# Decision Packet — O-003/O-004/O-005/O-010 Client Credit and Zero-Invoice Model

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Client Credit, Invoicing, Refunds, Budget Projection, Presentation
Unlocks: 26 unique residual surfaces (O-003: 13; O-004: 13; O-005: 20;
O-010: 13)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this combined policy:

> A paid-Item return creates a Project-scoped Client Credit with an exact
> original amount and remaining balance. It may be applied, in whole or in part,
> to a future positive Invoice in the same Project or paid back in cash. Applying
> credit is non-cash settlement and creates no Transaction. A cash refund creates
> one real Project Return linked to the credit. A nonempty Invoice whose positive
> sources and applied credits net to exactly zero closes through a typed credit-
> offset settlement with no Purchase. A net-negative or credit-only Invoice is
> not collectible; the remaining credit stays open or is cash-refunded, and any
> client document is a Credit Memo rather than a fake Invoice payment.

Budget projections retain signed paid/unpaid components. Credits are never
clamped or hidden: positive charge portions extend right of zero, credit portions
extend left, and the signed recognized net remains `paid + unpaid`. Settling a
credit moves the same negative contribution from unpaid to paid without changing
recognized value.

This packet uses the O-034 recommendation that a sent revision must be current
and delivered before settlement. If O-034 is rejected, the delivery gate must be
replaced explicitly rather than omitted.

## Confirmed Constraints

- Returning a paid Item preserves its original paid Invoice/Purchase and creates
  one deterministic negative credit from the frozen paid amount/category.
- No refund Transaction exists until money actually leaves 1584 for the Client.
- Purchase and Return mean actual Client money; Transfer is the only non-cash
  Transaction type.
- Whole-Invoice positive collection creates one Purchase. It never creates one
  payment per category and never double-counts source contributions.
- Paid/unpaid segment movement must preserve recognized Project value.
- Client credit, physical Item custody, vendor refund and accounting correction
  are separate facts/commands.
- Paid history is immutable; later credit/refund/offset evidence appends.

## Options

### Option A — Credits only reduce a future Invoice

Recommendation: reject. It cannot handle a Client who wants cash back or has no
future positive work.

### Option B — Credits only pay out in cash

Recommendation: reject. It forces unnecessary money movement when the Client and
1584 want to offset a later amount.

### Option C — Balance with explicit application or cash refund (recommended)

One stable credit can be consumed by one or more exact applications/refunds.
Every settlement is typed, idempotent and auditable.

## Client Credit Model

A `ClientCredit` carries:

- stable ID, Account, Client and owning Project;
- originating Item credit occurrence/frozen paid line/correction source;
- original positive magnitude, currency and category snapshot;
- remaining positive magnitude derived from accepted settlements;
- open/partially-settled/settled/canceled-or-corrected lifecycle;
- actor, effective time, reason and revision; and
- Transfer/provenance history required by O-014 where the paid Item moved.

The credit's budget contribution is signed negative. Magnitudes are stored as
positive cents in the credit/settlement rows; sign is derived from type. A
balance is never mutable client authority:

```text
remaining_credit_cents
  = original_credit_cents
  - accepted_invoice_application_cents
  - accepted_cash_refund_cents
```

Every settlement locks the credit and rederives this equation. Total settlement
cannot exceed original credit under retries or concurrency.

Initial application is limited to an Invoice in the same Project. Same-Client
cross-Project application changes Project attribution and is prohibited until a
separate approved reallocation model defines both Projects' budget/report effects.

## Invoice Credit Application

`ApplyClientCreditToInvoice` creates a live Invoice source/application with an
exact amount not exceeding the credit's remaining balance or the positive
sources being offset. It does not create or mutate a Transaction.

- The original Item credit remains one stable source; applications have their
  own stable IDs and amounts so partial use does not split or clone history.
- An application reserves that balance while its Invoice is active. Concurrent
  Invoices cannot reserve the same cents.
- Removing/canceling the application before settlement releases the reservation
  atomically and revises the Invoice under O-034.
- Collected/offset-settled application evidence is immutable. Later correction
  appends reversal/correction evidence and restores balance only through the
  approved correction command.
- The credit keeps its original Project/category attribution. It does not inherit
  a positive Invoice source's category.

## Invoice Terminal Cases

### Positive net total

If current delivered sources net to greater than zero, `CollectInvoice` creates
one Project Purchase for exactly that positive cash amount and freezes positive
sources plus credit applications. Frozen category allocations may contain both
positive and negative values. The Purchase face amount is payment evidence, not
a second budget contribution.

### Exactly zero with nonempty sources

If positive sources and credit applications net to exactly zero,
`SettleInvoiceByCreditOffset`:

- requires a current delivered/attested revision and exact source revisions;
- freezes the complete nonempty source set and credit applications;
- marks the Invoice `settled_by_credit` (or equivalent explicit terminal state);
- creates no Purchase or Return because no money moved;
- moves each positive and negative contribution from unpaid to paid/settled
  provenance without changing recognized totals; and
- writes one durable idempotent result and settlement event.

This is not a Transfer and not an exception to the Transaction taxonomy because
it creates no Transaction.

### Negative or credit-only total

A net-negative Invoice cannot be collected or offset-settled. The user may:

- reduce the applied amount so the Invoice is zero or positive;
- leave the unused credit balance open for a future same-Project Invoice; or
- refund some/all remaining credit in cash.

If a client-facing document is needed, generate a versioned Credit Memo from the
credit/refund evidence. Do not create a Purchase with negative amount, a zero
Purchase, or a fake payment.

### Empty zero Invoice

- A never-sent created Invoice that loses its final source is atomically canceled
  as `canceled_empty`, releases all live membership/reservations, and retains its
  event history. It is not physically deleted.
- A sent Invoice that loses its final source advances to a zero working revision
  and requires explicit `CancelZeroInvoice` plus cancellation delivery/attestation.
  Until accepted, it is noncollectible and visibly requires action.
- A paid/settled Invoice never becomes empty; corrections append evidence.

## Cash Refund

`SettleClientCreditAsCashRefund` requires exact credit revision, positive amount
not exceeding available balance, payment date/method/evidence, actor capability
and idempotency key. It atomically:

1. consumes the exact credit balance;
2. creates one Project Return representing actual money the Client received from
   1584;
3. links the Return to the credit/original paid evidence;
4. moves the corresponding negative contribution from unpaid to paid/refunded
   without changing recognized Project value; and
5. writes immutable refund and operation evidence.

The Return's category allocation comes from the settled credit/original frozen
source. Its face amount is real money evidence and is not counted in addition to
the frozen negative allocation. A vendor refund uses its own scope-relative
Return and never settles this Client credit automatically.

## Signed Budget Projection and Presentation

`ProjectBudgetSnapshot` exposes, per category and overall:

- `paid_charge_cents` and `paid_credit_cents` (positive magnitudes);
- `unpaid_charge_cents` and `unpaid_credit_cents` (positive magnitudes);
- signed `paid_net_cents = paid_charge - paid_credit`;
- signed `unpaid_net_cents = unpaid_charge - unpaid_credit`;
- signed `recognized_net_cents = paid_net + unpaid_net`;
- budget, remaining/over, contribution counts, revision and readiness; and
- pending-operation deltas separately from authoritative values.

The visual contract is a zero-centered diverging two-segment display:

- paid and unpaid charge portions extend right from zero;
- paid and unpaid credit portions extend left from zero;
- a signed net marker/label shows recognized value;
- paid versus unpaid uses both color and a non-color cue (label/pattern/icon);
- credit uses an explicit minus/“credit” label, never color alone;
- values are not clamped to zero or hidden when negative; and
- `remaining = budget - recognized_net`, so a net credit can legitimately make
  remaining exceed the original budget.

Compact Project cards may show the signed recognized net plus a “$X credit
pending” badge. They may not flatten pending credit into $0, label it paid, or
use a different arithmetic source than the detailed Budget view.

Examples:

| Paid | Unpaid | Recognized | Required explanation |
|---:|---:|---:|---|
| $100 | -$20 | $80 | $100 paid; $20 credit pending |
| $80 | $0 | $80 | $20 credit settled/applied/refunded; net paid allocation $80 |
| $0 | -$20 | -$20 | Client has a $20 pending credit; recognized is net credit |
| $0 | $0 | $0 | No recognized activity, not “credit hidden” |

Settlement changes segment ownership, not the final column.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `client_credits` | Original credit identity, Project/Client/category/source and lifecycle |
| `client_credit_reservations/applications` | Exact amount reserved/applied to one Invoice revision |
| `client_credit_cash_refunds` | Exact amount and linked real Return/payment evidence |
| Invoice settlement events | Positive collection versus zero credit-offset terminal evidence |
| frozen collected/settled allocations | Immutable signed source/category values and contribution succession |
| budget contributions/projection | Stable identity, paid/unpaid segment, signed cents, source/settlement correlation |
| Credit Memo artifacts | Private immutable client-facing credit/refund document and delivery audit |
| operation/results | Idempotency, payload hash, expected revisions and durable outcomes |

Use stable IDs, `bigint` cents, explicit currency, foreign keys and checks for
positive magnitudes/legal terminal states. Enforce at most one active reservation
per application, exact credit balance, same-Project application, and no Purchase
for zero/negative totals in trusted handlers. Index every foreign key/RLS key,
open credit by Project/Client, active reservation by Invoice/credit, settlement
history and contribution projection cursors.

## Atomicity and Concurrency

- Credit application/refund/settlement locks operation, Invoice/Transaction
  headers, credit IDs in stable order, source links/reservations, relevant Item/
  occurrence/frozen evidence, contributions and result rows.
- Revalidate Account/Client/Project, capabilities, current/delivered Invoice
  revision, source eligibility, remaining/reserved balance and exact net while
  locks are held.
- External payment, rendering, delivery and receipt work is prepared/verified
  outside the database transaction. The handler records real payment evidence;
  it does not initiate an unbounded external call while holding locks.
- Concurrent applications/refunds cannot overspend credit. Concurrent final-line
  removal, source edit, send and collection/offset settle serialize or return a
  typed conflict with no partial state.
- Retries use the same operation ID/payload hash and return the same result.

## Authorization, RLS, Sync, and Offline

- Credits, balances, applications, refund evidence and Invoice/budget effects
  are financial data. RLS/Sync requires active membership, Project access and
  exact financial capabilities/categories; physical Item visibility alone is
  insufficient.
- Restricted users receive no revealing credit counts, net totals, source names,
  operation errors or Credit Memo artifacts.
- Direct writes to balances/reservations/settlements/Returns/contributions are
  revoked. App and MCP call the same typed handlers.
- Project streams include authorized open credits/reservations, current Invoice
  sources, settlement summaries, budget snapshot and operation results needed
  offline. Historical detail/artifacts may use an on-demand stream with explicit
  completeness.
- Offline application/refund/settlement requests remain visibly pending and do
  not alter authoritative money/budget totals until accepted. A pending overlay
  may preview deltas separately.
- Cash refund cannot be claimed complete without accepted server evidence of the
  real payment. Logout/pending bytes follow the approved durability policy.

## Migration and Reconciliation

- Preserve legacy manual returned-Item credit lines, deterministic paid-line
  references, Invoices/status, payment/void Transactions, Item/lineage evidence,
  category snapshots, amounts and timestamps from immutable export.
- Map a negative line to Client Credit only when its origin, frozen paid amount,
  category, Item occurrence and duplicate-prevention identity are proven.
- Reconstruct applications/refunds only from explicit settlement/payment
  evidence. Do not infer cash from `paid`/closed status or net arithmetic.
- Net-positive paid Invoice maps to one Purchase only when exact payment evidence
  is proven. Net-zero source sets map to credit-offset settlement only under an
  approved evidence rule. Net-negative/credit-only legacy Invoices become credit/
  Credit Memo review, never negative Purchase.
- Preserve empty/zero sent Invoice and cancellation evidence with deterministic
  disposition. Unknown cases quarantine.

Reconcile each original credit, applications/reservations, cash Returns,
remaining balance, Invoice terminal state, frozen signed allocations, paid/
unpaid contribution succession, Project/category totals, artifacts and every
source-to-target/quarantine disposition. Repeated import must be idempotent.

## Required Acceptance Tests

### Credit balance and settlement

- deterministic paid-Item return creates one credit under retry;
- partial/full Invoice application and cash refund consume exactly the available
  balance with no overdraw under concurrent requests;
- same-Project constraint rejects cross-Project application without changing
  either budget;
- net-positive collection creates one exact Purchase; net-zero offset creates no
  Transaction; net-negative/credit-only collection rejects;
- cash refund creates one real Return and no duplicate budget contribution;
- vendor refund, physical movement and correction cannot settle Client credit;
  and
- removing/canceling an uncollected application restores reservation exactly.

### Zero Invoice and budget presentation

- empty created Invoice cancels atomically; sent empty Invoice requires explicit
  cancellation revision/delivery; paid history cannot be emptied;
- signed paid/unpaid/recognized/remaining arithmetic covers positive, mixed,
  zero and net-credit categories without clamping;
- collection, offset and cash refund move exact contribution identity unpaid to
  paid while recognized remains byte-for-byte/equal-cents unchanged;
- Project card, Budget view, Invoicing, MCP, report and export use the same
  snapshot values/labels;
- zero-centered rendering has textual minus/credit cues and passes accessibility,
  locale, currency and large-value snapshots; and
- partial/restricted readiness never renders as true zero.

### Security, offline, and migration

- cross-account/restricted-role/direct-table/forged source attempts cannot read,
  reserve, settle, refund or infer credit existence;
- offline apply/refund/settle survives restart, stays pending and converges to
  one accepted/rejected result without optimistic authoritative money;
- legacy credit-only/net-zero/duplicate/manual/paid-without-payment fixtures map
  deterministically or quarantine without invented Transactions; and
- source/target credit balances, actual money, frozen allocations and budget
  totals reconcile exactly.

## Approval Consequences

If approved:

1. update canonical Client credit, Invoice, Item return, Transaction, budget and
   presentation specs and record confirmed decisions;
2. promote credit balance/application/refund/zero-settlement and signed snapshot
   contracts into architecture 02/04/05/06/07;
3. remap the 26 affected residual surfaces while retaining O-014/O-023/O-029/
   O-033/O-034 and other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, operation contracts,
   projection fixtures and migration rules; and
5. include offline overdraw races, zero settlement, actual refund, accessibility
   and no-double-count tests in the target spike.

## Approval Checklist

- [ ] Client credit can be applied to future same-Project Invoice or refunded in
  cash, including partial settlement.
- [ ] Credit application creates no Transaction; cash refund creates one Return.
- [ ] Net-zero nonempty Invoice settles by credit offset with no Transaction.
- [ ] Net-negative/credit-only Invoice is not collectible; use open credit/Credit
  Memo/cash refund.
- [ ] Empty created Invoice cancels; empty sent Invoice requires explicit
  cancellation delivery.
- [ ] Paid/unpaid charge and credit components remain signed and visible.
- [ ] Settlement changes segment ownership without changing recognized value.
- [ ] Cross-Project credit use remains prohibited until separately modeled.
