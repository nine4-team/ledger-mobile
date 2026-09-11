# Decision Packet — O-009/O-034 Invoice Adjustments and Sent Revisions

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Invoicing, Client Adjustments, Rendering/Delivery, Collection, Audit
Unlocks: 20 unique residual surfaces (O-009: 15; O-034: 15; overlap: 10)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this combined direction:

> Keep the ability to add an exceptional manual Client charge or credit, but
> “manual” is only how it was captured. The canonical source is a typed,
> Project-scoped `ClientAdjustment` with sign, exact cents, category, reason,
> actor and revision. Generic Invoice-only lines with no source identity are
> retired. Created and sent Invoices remain financially live until collection,
> but every source-value or membership change after first send creates a new
> monotonic Invoice revision. The changed revision must be rendered and delivered
> (or explicitly attested as delivered) before it can be collected. Previously
> delivered revisions and delivery evidence remain immutable.

O-009 and O-034 are coupled because a source-less mutable manual line cannot be
versioned, delivered, conflicted or frozen with the same guarantees as Item,
Expense and Fee sources.

This packet does not approve partial collection, actual-payment variance,
zero-dollar Invoice closure, credit settlement, or collected-accounting
correction. Those remain under O-003/O-004/O-010/O-029/O-033.

## Confirmed Constraints

- Item occurrences, Expenses, Fees and approved adjustments are live Invoice
  sources until whole-Invoice collection.
- A source belongs to at most one active uncollected Invoice.
- Send does not freeze financial values; collection freezes exact final sources,
  categories and allocations and creates one Project Purchase.
- Collection moves recognized value from unpaid to paid without adding spend.
- Returned-paid-Item credit is a typed Item credit occurrence, not a generic
  manual line.
- Cash refund is a real Return. A Client adjustment/credit is demand evidence and
  does not invent money.
- Paid history and client-facing delivered versions are immutable.
- App and MCP cannot supply authoritative amounts for source-backed lines.

## O-009 Options — Manual Adjustments

### Option A — Retire all manual adjustments

Recommendation: reject. Exceptional one-time contractual charges/credits exist
that are not honestly Items, Expenses or recurring Fees. Forcing them into those
types would corrupt provenance.

### Option B — Keep source-less Invoice lines

Recommendation: reject. They have no independent revision, availability,
category/authorization boundary, budget contribution identity or migration
correlation.

### Option C — Typed ClientAdjustment source (recommended)

Create a canonical source before Invoice membership. Capture method may be
manual, MCP, import review, or system-generated, but source semantics remain
typed and auditable.

## ClientAdjustment Contract

A `ClientAdjustment` represents one exceptional Project-scoped amount the
Client owes 1584 (`charge`) or 1584 owes/credits the Client (`credit`) that is not
better represented by Item occurrence, Expense, Fee, Purchase/Return, Transfer,
or Invoice correction.

Required evidence:

- stable ID, Account, Project and Client correlation;
- `charge` or `credit` kind with positive magnitude and derived signed cents;
- explicit currency and enabled visible category;
- required description and typed reason code plus optional note/evidence;
- actor, capture source, creation/effective time and revision;
- available/invoiced/settled/canceled-or-reversed lifecycle; and
- source/correction/reversal correlation where applicable.

Initial allowed reason families should be explicit and small, for example:

- contractual scope addition/reduction;
- goodwill/service adjustment;
- approved miscellaneous Client charge/credit; and
- approved conversion of legacy manual evidence.

The implementation must not use an “other” reason to bypass a better source
type. Returned paid Item, reimbursable Business expense, Fee installment,
receipt rounding, actual cash, transfer, tax allocation and collection variance
route to their owning contracts.

The default category may be the reserved system “Other Client Charges & Credits”
category, but the handler must still verify its stable system identity and
financial visibility. User-editable text cannot create or impersonate a system
category.

### Adjustment mutability

- Available and uncollected: approved fields may change with expected revision.
- On a created Invoice: source changes atomically revise the source and Invoice.
- After first send: the same source change creates a new working Invoice revision
  and requires delivery before collection.
- Settled: immutable. A new reversing/correcting source is appended; the frozen
  paid allocation remains.
- Cancellation is allowed only while uncollected and dependency-safe. It releases
  active Invoice membership through the Invoice revision command; it does not
  delete evidence.

## O-034 Options — Sent Invoice Changes

### Option A — Mutate sent contents silently

Recommendation: reject. The system cannot prove what the Client saw, and a user
could collect a total that was never delivered.

### Option B — Freeze everything at send

Recommendation: reject because it contradicts D-011. Created and sent source
values remain live until collection.

### Option C — Live working revision plus immutable delivered revisions
(recommended)

Maintain one current working revision derived from live sources and immutable
render/delivery evidence for every sent version. Any financial/membership change
after send requires an explicit revised delivery before collection.

## Invoice Revision and Delivery Model

An Invoice has:

- stable Invoice ID and monotonic revision number;
- one current working revision/source set;
- zero or one latest successfully delivered revision;
- lifecycle `created`, `sent`, `paid`, or `canceled` plus explicit readiness;
- render and delivery state independent from financial state; and
- an append-only event stream.

Each revision freezes client-facing presentation for that version:

- stable ordered source identities and source revisions;
- descriptions, quantities if applicable, signs, exact cents, categories and
  currency;
- subtotal/total and Invoice metadata/notes/payment instructions;
- rendering template/version and content hash; and
- creation cause/actor/time and predecessor revision.

Live sources remain authority for the current working revision. Revision rows
are immutable client-facing snapshots, not competing accounting sources.

### State transitions

1. A created Invoice may revise source membership/presentation under expected
   revisions. Nothing has been delivered.
2. `SendInvoice` freezes the current working revision, renders it, records a
   delivery attempt, and marks `sent` only after an accepted delivery event or
   explicit authorized manual-delivery attestation.
3. A later source amount/category/description or membership change atomically
   advances the working revision and marks `revision_delivery_required`. The
   prior delivered revision remains available in history.
4. `SendInvoiceRevision` renders/delivers that exact working revision and, on
   success/attestation, advances `latest_delivered_revision`.
5. `CollectInvoice` requires the current working revision to equal the latest
   delivered revision and revalidates every live source/revision. It freezes
   those sources and collected allocations in the same transaction as the one
   Purchase and paid state.

A delivery provider accepting a message is audit evidence, not proof the Client
read it. Manual delivery attestation records actor, method, time, recipient and
reason. Failed rendering/delivery never marks a revision delivered or collectible.

### Membership effects

- Adding/removing/reordering a source after send uses
  `ReviseSentInvoiceSources`, not a generic line patch.
- A removed source becomes available to other Invoices only after the revision
  command commits. Historical revisions continue to reference it.
- Source active-membership uniqueness applies to the current working source set,
  not immutable historical revisions.
- Removing the final source follows O-010. This packet does not silently cancel
  or collect a zero-dollar Invoice.
- O-002 governs Transfer-driven source removal; if permitted, it still creates
  and requires delivery of a new revision.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| `client_adjustments` | Typed signed source, reason/category/revision/lifecycle |
| `invoice_source_links` | Current live membership and expected source revision |
| `invoice_revisions` | Immutable monotonic client-facing revision header/hash/cause |
| `invoice_revision_sources` | Immutable ordered exact source snapshot for one revision |
| render artifacts | Private immutable rendered bytes/hash/template version and retention reference |
| `invoice_delivery_events` | Attempt/accepted/failed/manual-attested evidence and safe provider correlation |
| collected source/allocation rows | Immutable exact paid membership/categories linked to one Purchase |
| Invoice events and operation/results | Idempotency, actor, transitions, rejection/conflict evidence |

IDs are stable and client-allocatable where offline creation requires them.
Money is `bigint` cents; times are `timestamptz`; current source relationships use
foreign keys. Enforce unique current active membership by typed source identity,
unique `(invoice_id, revision_number)`, immutable revision rows, and collection
only for the latest delivered revision. Index every foreign key/RLS predicate,
current source eligibility, Project Invoice lists and revision/delivery history.

## Commands and Queries

- `CreateClientAdjustment`, `ReviseOpenClientAdjustment`,
  `CancelOpenClientAdjustment`, and typed correction/reversal;
- `CreateInvoice`, `ReviseCreatedInvoiceSources`, `SendInvoice`,
  `ReviseSentInvoiceSources`, `SendInvoiceRevision`, `CancelInvoice`, and
  `CollectInvoice`;
- `InvoiceEditorSnapshot` with working/delivered revisions, source eligibility,
  readiness and pending operations;
- immutable `InvoiceRevisionHistory` and authorized artifact/delivery audit; and
- canonical `ProjectBudgetSnapshot`, where an active adjustment contributes once
  to unpaid and its frozen collection allocation succeeds it once in paid.

There is no target generic `AddInvoiceLine(amount:)`, source-less line, raw
status/membership patch, direct render URL, client-supplied source amount,
selected-line collection, or “mark paid” command.

## Atomicity and Concurrency

Source or membership revision locks the operation, Invoice header/current
revision, affected sources in stable type/ID order, active source links, and
projection/result rows. It revalidates eligibility, exclusivity, category,
financial visibility and expected revisions before atomically appending the new
working revision/event.

Rendering and delivery are external and use an outbox:

```text
accepted revision -> render pending -> artifact verified -> delivery pending
                  -> accepted/attested or retryable/permanent failure
```

No external render/email/storage call occurs inside the database transaction.
Jobs use idempotent revision/content hashes. A stale render or delivery result
cannot advance a newer working revision.

Collection follows the common deterministic lock order, requires latest working
equals delivered, and freezes sources/allocations/Purchase/result atomically.
Concurrent source edit, removal, send and collection either serialize on one
revision or return a typed conflict with no partial payment/history.

## Authorization, RLS, Sync, and Offline

- Adjustment/Invoice read and mutation require active Account membership,
  Project access and the exact financial capabilities/categories. Restricted
  members cannot infer hidden source/revision/artifact/delivery counts or totals.
- Direct writes to source links, revision snapshots, delivery state, collection
  evidence and budget contributions are revoked. App/MCP use the same handlers.
- Render/delivery workers have narrow server credentials and cannot change live
  source money. Provider payload/logs contain only necessary authorized data.
- Artifacts are private attachments with immutable evidence holds under O-023;
  signed access is short-lived and never persisted in Sync rows.
- Offline create/revise/send requests are durable operations. Pending local
  revisions are clearly pending and cannot claim delivered/collectible status.
  Rendering/delivery starts only after server acceptance.
- Selected Project streams include authorized Invoice summaries, current source
  links/revisions, latest delivered metadata, pending operation/results and
  budget/readiness. Historical revision artifacts may use an on-demand stream
  with explicit completeness.

## Migration and Reconciliation

- Preserve every Firebase Invoice/line/member array, manual line, sent snapshot,
  event, PDF/reference, recipient/delivery evidence, settlement link and source
  record from the immutable export.
- Generate deterministic stable source IDs for source-less manual lines using
  Invoice ID, line identity/ordinal, normalized content, original timestamps and
  migration version. Never use runtime random IDs.
- Map a manual returned-Item credit to the exact typed Item credit occurrence
  when provenance and cents are proven. Map a Fee/Expense disguised as manual to
  that source only with exact evidence. Remaining legitimate exceptional lines
  become migration `ClientAdjustment` records with explicit legacy reason/
  confidence; ambiguous lines quarantine.
- Current created/sent membership becomes the working source set only after
  eligibility/exclusivity reconciliation. Historical stored lines/snapshots are
  immutable legacy revision evidence with provenance/confidence.
- Do not claim provider delivery where none exists. A source “sent” status may
  create a legacy delivery attestation only under an explicitly reviewed mapping
  policy; otherwise delivery status is unknown and collection repair remains
  reviewable.
- Paid Invoices map frozen collected sources only when settlement/Purchase and
  exact cents are proven. Stored paid status alone cannot invent collection.

Reconcile every Invoice/manual line/source, revision number/hash, delivered/
unknown status, active-membership uniqueness, source cents/category/sign,
artifact/reference, settlement/Purchase, budget contribution and quarantine
reason. Repeat/interrupted migration must produce identical IDs and hashes.

## Required Acceptance Tests

### Adjustment semantics

- charge/credit sign and positive magnitude produce exact signed contribution;
- Item return credit, Expense, Fee, cash Return, rounding and Transfer cannot be
  misclassified as generic adjustment;
- uncollected edit/cancel revises membership atomically; collected adjustment is
  immutable and correction appends new evidence;
- system category identity/financial visibility is enforced server-side; and
- app/MCP/import use identical validation and reason taxonomy.

### Revision, delivery, and collection

- first send creates immutable revision/artifact/delivery evidence without
  freezing the live source permanently;
- source value/category/membership change after send creates the next revision,
  retains the prior delivered version and blocks collection until resend;
- failed/stale render or delivery cannot mark current revision delivered;
- authorized manual delivery attestation is immutable and bound to exact
  revision/hash/recipient/method;
- removing a source releases current exclusivity only after commit; prior
  revisions remain explainable;
- concurrent edit/send/remove/collect produces one serial result with no double
  membership or Purchase; and
- collection accepts only exact current delivered revision and preserves total
  recognized budget while moving unpaid to paid.

### Security, offline, and migration

- cross-account/restricted-category/direct-table/artifact-path attempts fail
  without counts/totals/existence leakage;
- offline revision/send survives restart, stays visibly pending, and never
  claims delivered or paid before server result;
- private artifacts obey attachment holds and reveal no durable token/path;
- source-less, duplicate-ID, returned-Item-credit, ambiguous-manual, sent-without-
  delivery and paid-without-settlement fixtures receive deterministic mappings
  or quarantine; and
- app, MCP, budget, report and export resolve the same revision/source authority.

## Approval Consequences

If approved:

1. update canonical Invoice/adjustment/budget specs and record confirmed
   decisions;
2. promote typed adjustment and revision/delivery contracts into architecture
   02/04/05/06/07;
3. remap the 20 affected surfaces, retaining O-003/O-004/O-006/O-010/O-023/
   O-029/O-033 and other independent blockers;
4. design reviewed constraints/indexes, RLS/Sync profiles, rendering outbox,
   migration fixtures and behavioral tests; and
5. include offline revision, render/delivery retry and collection-race cases in
   the target spike.

## Approval Checklist

- [ ] Exceptional manual capability remains as typed `ClientAdjustment` source.
- [ ] Generic source-less Invoice lines are retired.
- [ ] Returned-Item credit/Expense/Fee/cash/Transfer/rounding use their real types.
- [ ] Created and sent source money remains live until collection.
- [ ] Any post-send source or membership change creates a monotonic revision.
- [ ] Collection requires the exact current revision to be delivered/attested.
- [ ] Delivered revisions/artifacts/events remain immutable and private.
- [ ] Rendering/delivery use an idempotent outbox outside database transactions.
- [ ] O-003/O-004/O-010/O-029/O-033 remain open and are not resolved here.
