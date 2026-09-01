# Decision Packet — O-006/O-033 Expense Locks and Collection Payment

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Expenses, Invoicing, Collection, Payment Evidence, Corrections
Unlocks: 14 unique residual surfaces (O-006: 9; O-033: 10; overlap: 5)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this combined policy:

> An Expense remains an editable live source until collection, but all changes
> are revision-safe and classified as financial/client-facing or internal
> evidence. Changes that affect amount, category, sign, description, or any field
> rendered to a sent Invoice advance the Invoice revision and require revised
> delivery under O-034. Collection freezes the exact Expense revision. After
> collection, accounting/client-facing fields are immutable; corrections append
> typed evidence and replacement allocations. Internal notes may be appended and
> supplementary evidence may be attached, but original retained evidence cannot
> be detached through ordinary edit.

> Initial-release `CollectInvoice` requires the actual positive Client payment
> to equal the authoritative current delivered Invoice total exactly. Underpay,
> overpay, zero, negative, partial, and selected-line amounts reject atomically.
> If real mismatched payment evidence must be captured, preserve it as a durable
> noncanonical payment-evidence draft/review item under O-032; do not mark the
> Invoice paid or invent a discount, fee, credit, allocation, Purchase, or Return.

The topics overlap because an operator must not edit an Expense silently to
force an Invoice to match cash that arrived.

## Confirmed Constraints

- A 1584-paid non-itemized Project cost is an Expense in Invoicing, not a Project
  Transaction.
- Created and sent Invoices remain live until collection; paid source revisions
  and frozen allocations are immutable.
- Whole-Invoice collection creates one Project Purchase for actual positive
  Client payment and no category-split or partial payments.
- Collection moves source contribution unpaid to paid without changing total
  recognized value or counting the Purchase face amount twice.
- App/MCP caller values are not Invoice/source authority. Collection re-reads
  current source membership and revisions inside the trusted transaction.
- O-008/O-030 define receipt-line treatment/rounding; O-009/O-034 define typed
  adjustment and sent-revision delivery; O-023 defines attachment retention.

## Options

### Option A — Freeze every Expense field at Invoice membership

Reject. It is safe but prevents correcting internal/vendor/evidence fields that
do not change the Client-facing amount or rendered artifact.

### Option B — Keep all fields live and accept arbitrary collection variance

Reject. It permits silent delivered-Invoice drift and invents unspecified
underpayment, overpayment, fee, discount, or write-off semantics.

### Option C — Consequence-based field matrix plus exact collection equality
(recommended)

Permit revision-safe live changes according to their financial/rendering effect,
require resend for affected sent revisions, freeze collected facts, and collect
only when actual positive payment exactly equals the current delivered total.
Preserve mismatched real-world evidence as noncanonical review rather than
fabricating settlement.

## Expense Field Matrix

Fields are grouped by consequence rather than storage location.

| Field family | Available, not on Invoice | On created Invoice | On sent Invoice | Collected |
|---|---|---|---|---|
| amount, currency, charge/credit sign | revise with expected version | revise Expense + Invoice working revision atomically | revise Expense + new Invoice revision; resend required | immutable; typed collected-accounting correction only |
| category/allocation | revise after enabled/visibility/dependency checks | revise source + Invoice/budget atomically | new Invoice revision; resend required | immutable; typed reallocation correction only |
| client-facing description/quantity | revise | revise working Invoice | new Invoice revision; resend required | immutable; append correction/replacement evidence |
| payer/scope/Project/Client identity | not ordinary edit; typed correction before history | blocked or typed correction that revises membership | blocked unless full audited correction/recall is approved | immutable; administrative correction workflow only |
| vendor/effective date/payment method | revise with evidence audit | revise Expense; revise Invoice only if rendered/client-visible | revise Expense; if rendered, new Invoice revision/resend | append metadata correction with before/after/reason; frozen rendered value unchanged |
| receipt/original attachment | attach/replace under O-023 with audit | same; Invoice revision if rendered | same; resend if rendered | original held; supplementary attach allowed, supersede only through correction |
| internal note | append/revise current note with audit | no Invoice revision unless rendered | no resend unless rendered | append-only internal note; no rewrite of frozen client evidence |
| cancel | allowed if dependency-free | remove live membership + cancel atomically | new cancellation/removal revision and delivery under O-034 | prohibited; use collected correction/refund/credit story |

Whether a field is rendered is explicit template/revision metadata, not guessed
from UI visibility. A field added to a client template becomes client-facing for
that revision and follows resend/immutability rules.

## Expense Commands

- `CreateExpense` validates 1584 payer, Project/Client/category, exact cents,
  currency, effective date, receipt-treatment readiness and actor capability.
- `ReviseOpenExpenseFinancials` changes amount/category/sign/client description
  and atomically revises any active Invoice/source contribution.
- `ReviseExpenseEvidence` changes eligible internal/vendor/date/evidence fields
  and determines from the active rendering contract whether Invoice revision is
  also required.
- `CancelOpenExpense` releases active membership, closes unpaid contribution and
  preserves cancellation evidence; sent membership follows O-034 delivery.
- `CorrectCollectedExpense` is not ordinary CRUD. It appends typed before/after/
  reason/approval evidence and replacement allocation or separate credit/refund
  effects without rewriting frozen Invoice/Purchase rows.

There is no generic Expense dictionary patch, raw Invoice-line update, direct
status toggle, or delete after synchronization.

## Exact Collection Payment

`CollectInvoice` receives or resolves payment evidence containing amount,
currency, effective time, method/reference, attachment IDs if any, actor and
operation ID. While holding authoritative locks it requires:

```text
actual_payment_cents == current_delivered_invoice_total_cents
actual_payment_cents > 0
currency matches exactly
```

It also requires current working revision equals current delivered revision and
all source/category/credit application revisions remain eligible. The caller
cannot omit amount and ask the server to pretend a payment occurred; a provider
or manual payment record must explicitly support the exact amount.

Rejected mismatch outcomes are typed (`underpayment`, `overpayment`, `zero`,
`negative`, `currency_mismatch`, `stale_invoice_revision`) and include the safe
expected/received values only for authorized financial users.

### Resolving a mismatch

The initial release permits these honest paths:

1. correct mistaken payment-entry evidence and retry with the same actual event;
2. revise legitimate Invoice sources or add a typed ClientAdjustment, deliver
   the new revision, then collect if its total truly equals the payment; or
3. capture the unmatched real-world evidence as a durable
   `PaymentEvidenceDraft`/migration-review item for later resolution.

Path 2 must reflect a real business change, not a fabricated balancing line.
Path 3 does not mark the Invoice paid, create a Purchase, affect budget, consume
credit, or claim cash reconciliation. It preserves amount/currency/date/method/
attachments and missing-decision reason under the O-032 draft/review boundary.

Partial payment, deposit, gratuity/fee, write-off, under/overpayment balance and
unapplied-cash accounting require a later explicit model. They are not smuggled
into the first release through “variance cents.”

## Collection Atomicity

Within one short database transaction, the handler locks in shared order:

1. operation/idempotency row;
2. Invoice/current/delivered revision and payment-evidence identity;
3. live sources (including Expenses) by stable type/ID;
4. credit reservations, categories and source dependencies;
5. contribution/frozen allocation/Purchase rows; and
6. event/projection/result rows.

It revalidates authorization, exact payment, source set/revisions, delivery,
currency and dependency state; freezes exact source revisions/allocations;
creates one Purchase; moves contribution identity unpaid to paid; marks the
Invoice paid; and records the result atomically.

No email, media upload, receipt parsing, payment-network call, PDF rendering or
other external action occurs while locks are held. External evidence is prepared
and verified beforehand or coordinated through an idempotent outbox. Retry keeps
the same operation/payment identity and cannot create a second Purchase.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `expenses` | Stable Project source, financial/client-facing fields, current revision and state |
| Expense evidence/attachments/notes | Typed internal evidence with audit and O-023 retention |
| Expense events/corrections | Append-only revisions, cancellation and collected corrections |
| Invoice source/revision rows | Current membership and immutable delivered/frozen source revision |
| payment evidence | Exact positive amount/currency/date/method/reference and verification status |
| payment evidence drafts/review | Durable noncanonical unmatched/incomplete evidence, no accounting effect |
| collection Purchase/frozen allocations | One actual payment plus immutable signed category/source membership |
| operation/results | Idempotency, payload hash, expected revisions and typed mismatch/conflict result |

Use stable IDs, `bigint` cents, explicit currency, `timestamptz`, foreign keys
and state/check constraints. Index every foreign key/RLS key, active Expense
eligibility, Invoice source/revision, payment identity and review queue. Enforce
active source uniqueness and payment/event idempotency. Use partial indexes for
open Expenses/pending review and equality-first/keyset indexes for Project lists.

## Authorization, RLS, Sync, and Offline

- Expenses, payment evidence, Invoice sources and budget allocations are
  financial data. RLS/Sync requires active membership, Project access and exact
  financial/category capabilities. Restricted users receive no hidden counts,
  vendor names, amounts, mismatch values or operation-result leakage.
- Direct canonical Expense financial/status, Invoice membership, payment,
  collection, contribution and correction writes are revoked. App and MCP call
  the same handlers.
- Project streams include authorized open Expense summaries/revisions, active
  Invoice membership, collected snapshot references, budget/readiness and
  operation results. Detailed receipt/payment evidence may use a bounded on-
  demand stream with explicit completeness.
- Offline Expense edits and collection submissions are durable operations.
  Pending edits/payment remain labeled pending; authoritative Invoice/budget/
  paid state does not change before server acceptance.
- Concurrent Expense edit/cancel, Invoice revise/send, credit application and
  collection serialize or conflict with no partial source/Purchase/projection.

## Migration and Reconciliation

- Preserve source non-itemized Transaction, payer/reimbursement flags, vendor,
  dates, amounts/currency/category, receipt/non-Item lines, attachments, Invoice
  membership, settlement/status and edit/correction evidence.
- Map to Expense only when 1584 payer, Project, exact money, category/treatment
  and nonphysical story are proven. Client-paid costs remain Purchases; ambiguous
  rows enter review.
- Infer field revisions/render visibility only from preserved Invoice snapshots/
  events/templates. Do not claim delivery or freeze merely from current status.
- Map one collection Purchase only when exact positive payment evidence equals
  the reconciled delivered Invoice total. Mismatched/ignored caller amounts,
  selected-line and category-grouped legacy settlements require explicit review;
  they do not auto-consolidate.
- Preserve unmatched payment evidence without inventing a balancing adjustment
  or paid Invoice.

Reconcile every source Expense candidate/disposition, revision, Invoice link,
rendered/client-facing value, exact payment, collection cardinality, frozen
allocation, contribution transition, attachment hold and review reason. Repeated
import produces identical IDs/results.

## Required Acceptance Tests

### Expense matrix

- every field family passes allowed/blocked/revision/resend/freeze behavior in
  available, created, sent and collected states;
- rendered versus internal-only evidence correctly determines Invoice revision;
- open cancellation releases membership/contribution; collected cancellation/
  delete/direct patch fails;
- collected correction appends evidence without rewriting frozen rows; and
- app/MCP use identical validation, event and error taxonomy.

### Payment and concurrency

- exact positive amount/currency/current-delivered revision creates one Purchase
  and unchanged recognized total;
- under/over/zero/negative/currency mismatch/partial/selected-line submissions
  create no Purchase, paid state, frozen allocations or contribution changes;
- unmatched evidence draft survives restart but has no accounting effect;
- concurrent Expense edit/collection, source removal/collection, send/collection
  and duplicate collection return one serial/idempotent outcome; and
- deadlock/serialization retry never duplicates payment/Purchase/events.

### Security, offline, and migration

- cross-account/restricted-role/direct-table/forged payment attempts fail without
  amount/vendor/source/result leakage;
- offline edit/collect/restart/reconnect remains visibly pending and converges to
  one result;
- exact, ignored-amount, grouped, partial, missing-payment and ambiguous-Expense
  fixtures map deterministically or quarantine; and
- target Expense/payment/Invoice/budget totals and frozen membership reconcile
  with zero unexplained differences.

## Approval Consequences

If approved:

1. update canonical Expense/Invoice/collection/Transaction/offline specs and
   record confirmed decisions;
2. promote field-state and exact-payment contracts into architecture 02/04/05/
   06/07 and the O-029/O-032 lifecycle proposal;
3. remap the 14 affected surfaces while retaining O-008/O-023/O-029/O-030/O-034
   and other independent blockers;
4. specify reviewed constraints/indexes, RLS/Sync profiles, operation locks,
   payment evidence and migration fixtures; and
5. include field-matrix, exact-payment and edit/collection race tests in the
   target spike.

## Approval Checklist

- [ ] Expense edits are classified by financial/client-facing/internal effect.
- [ ] Sent client-facing changes require a new delivered revision.
- [ ] Collection freezes the exact Expense revision; collected financial values
  are corrected append-only.
- [ ] Actual positive payment must equal the current delivered total exactly.
- [ ] No partial/selected-line/variance/zero/negative collection in the initial
  release.
- [ ] Unmatched payment evidence may be captured only as noncanonical review,
  with no Purchase/paid/budget effect.
- [ ] Users cannot edit an Expense merely to force a payment match.
