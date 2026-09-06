# Decision Packet — O-029/O-032 Transaction Posting and Lifecycle

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Transaction Capture, Accounting, Offline Operations, Migration
Unlocks: 36 unique residual surfaces (O-032: 23; O-029: 20; overlap: 7)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this combined contract:

> A Purchase or Return becomes canonical only through an atomic `PostTransaction`
> command after all posting evidence passes. Before that point it is a durable,
> explicitly nonfinancial capture draft. Once posted, the financial record and
> its evidence are never physically deleted through ordinary app or MCP
> operations. Mistakes use typed append-only correction or void evidence;
> actual opposite money uses a real Purchase or Return, not a void.

O-029 and O-032 should close together. “Can this be deleted?” cannot be answered
without knowing when the record first became financial authority. Conversely, a
posted/draft distinction is unsafe unless the terminal lifecycle and retention
rules are defined.

This packet proposes product and target contracts. It is not DDL, provider
approval, implementation authorization, production migration authorization, or
permission to change the running Firebase app.

## Confirmed Constraints

- Project Purchases and Returns represent actual Client money; Inventory
  Purchases and Returns represent actual Business money. Transfer is the only
  non-cash Transaction type.
- Physical movement, pending Client credit, vendor cancellation/account credit,
  Client cash refund, and accounting correction are not interchangeable with a
  Purchase or Return.
- Whole-Invoice collection creates its one Purchase through the collection
  command, not the ordinary Transaction capture path.
- A posted record cannot become valid merely because a later trigger fills an
  `isComplete` flag. App and MCP must share one posting boundary.
- Offline capture must survive process death. An offline post request can be
  accepted locally as pending, but must not be represented as authoritative
  money before the trusted handler accepts it.
- Paid Invoice membership, Item provenance, Transfer pairs, attachments and
  audit evidence must not be orphaned by deletion.
- The Firebase source has incomplete, canceled, deleted and tombstoned variants.
  Migration must classify them; source mechanics do not define target lifecycle.

## Options

### Option A — Continue canonical CRUD plus `isComplete`

Create a canonical Transaction early, let clients edit it freely, and derive a
completeness flag later.

Recommendation: reject. It allows incomplete rows to enter budgets and reports,
makes offline conflict behavior ambiguous, and repeats the current app/MCP and
rule divergence.

### Option B — Explicit draft, atomic post, append-only lifecycle (recommended)

Keep capture drafts outside canonical accounting. Post only through a trusted,
idempotent command. Preserve posted records and append typed lifecycle evidence.

Recommendation: approve. It gives capture speed without allowing incomplete
money to become accounting authority and makes migration/reconciliation honest.

### Option C — Every edit is an event and all Transactions are event-sourced

Store every keystroke/change in a universal event log and derive both drafts and
posted Transactions from replay.

Recommendation: reject for now. Ledger needs immutable financial evidence, not
the operational cost of universal event sourcing.

## Recommended State Model

```text
capture draft --request post--> pending post --accepted--> posted
      ^                              |
      |                              +--rejected/conflict--> capture draft + durable result
      |
      +--editable/discardable before posting

posted --typed metadata correction--> posted + correction event
posted --proved erroneous posting--> voided + immutable void event/effects
posted --material replacement-------> voided original + new posted replacement + correlation
posted --actual opposite money------> posted original + new Purchase/Return + economic correlation
```

Rules:

- `capture draft` is durable work, not a Transaction and not budget/report/
  Invoice authority.
- `pending post` is a local operation state. It may show the submitted preview,
  but financial totals remain authoritative-only until acceptance.
- `posted` is the only ordinary Purchase/Return accounting state.
- `voided` means the record was proven to have been posted in error. It remains
  queryable and auditable and contributes no active accounting value after the
  effective void.
- There is no “unvoid” mutation. A mistaken void is corrected with new explicit
  evidence.
- `deleted` is not a target canonical Transaction state. Legacy deletion and
  tombstone evidence is preserved in migration/audit records.

Transfer is posted only through `TransferItems`; Invoice collection is posted
only through `CollectInvoice`. Neither uses the generic capture draft/post path.

## Minimum Posting Evidence

`PostTransaction` requires a versioned evidence profile for the selected story.
Every Purchase/Return requires:

- stable client-allocated operation and draft IDs;
- authenticated actor, Account, explicit scope owner, and enabled Project or
  Inventory destination;
- canonical type `purchase` or `return` and a story that is legal for that
  scope/payer;
- positive final integer cents, explicit currency, and effective `timestamptz`;
- at least one typed accounting component/allocation whose signed cents
  reconstruct the final amount exactly under O-030/O-031;
- category/allocation values valid for the scope and actor;
- story-required counterparty/source evidence and correlation IDs;
- expected revisions for every referenced Item, Invoice source, draft,
  attachment, category, Project, or prior Transaction; and
- retained reason/source metadata sufficient to explain whether it is ordinary
  money, an actual refund, an Invoice collection, or a correction replacement.

Evidence profiles may add requirements. Examples:

- an Item acquisition requires the exact Item participation/acquisition roles;
- an actual vendor refund requires the vendor/refund evidence and may link a
  prior acquisition or disposition;
- Invoice collection requires exact Invoice revision/source freeze/payment
  equality and is accepted only by `CollectInvoice`; and
- a replacement correction requires original Transaction, reason, approver if
  required, and a dependency-safe plan.

A receipt image, vendor name, payment method, or Item is not universally
mandatory unless its evidence profile requires it. Missing optional evidence is
reported separately from posting validity. A generic mutable `isComplete`
boolean is not authority.

Zero-value Purchases/Returns are rejected. Transfer value is governed by the
Transfer contract. Credit demand and vendor account credit use their dedicated
non-Transaction records.

## Draft Contract

### User capture drafts

- A `TransactionCaptureDraft` has stable identity, owner/account, intended
  scope/story, fields, retained local attachment references, revision, and
  explicit readiness/missing-evidence output.
- It is encrypted and durable locally before the UI reports save success.
- It may be synchronized for authorized cross-device/team continuation, but the
  synchronized representation remains excluded from accounting RLS/query views,
  budgets, Invoices, reports, and exports unless the export explicitly asks for
  draft work.
- `SaveTransactionDraft` is revision-safe and idempotent. `DiscardTransactionDraft`
  may physically remove a never-posted draft only after pending operations and
  retained attachment references are resolved under O-023.
- A successful post consumes/freezes the exact draft revision. Later local edits
  create a new draft or correction request; they cannot mutate the posted row.

### Migration review records

Incomplete or contradictory Firebase Transactions do not become ordinary user
drafts. They enter a separate migration-review/quarantine family carrying raw
source evidence, reason codes, proposed classification, reviewer decisions and
source-to-target correlation. Promotion uses the same canonical posting
validation, plus an administrative migration capability and immutable review
receipt.

## Lifecycle Commands

| Command | Availability and effect |
|---|---|
| `SaveTransactionDraft` | Create/revise nonfinancial capture work; never changes accounting |
| `DiscardTransactionDraft` | Delete only a never-posted draft after operation/reference checks |
| `PostTransaction` | Validate the exact draft/evidence revision and atomically append one canonical Purchase/Return plus components and result |
| `CorrectPostedTransactionMetadata` | Correct only approved non-economic fields; append before/after/reason evidence |
| `ReplaceErroneousTransaction` | Atomically void an erroneous posted record and post one corrected replacement with explicit correlation |
| `VoidErroneousTransaction` | Mark a proven erroneous posting inactive, append immutable void/contribution evidence, retain all dependencies |
| `RecordActualRefund` | Create a real Return when money was received; never masquerade as void |

There is no ordinary `DeleteTransaction`, `DeleteSupersededTransaction`, raw
status patch, generic field patch, or independent deletion of a Transfer half,
Invoice collection Purchase, frozen allocation, or correction event.

## Dependency and Confirmation Policy

Before correction, replacement, or void, the trusted handler calculates a
versioned dependency plan covering:

- Item acquisition/client-paid membership and current/historical placement;
- open occurrence, Invoice membership, collection and frozen allocation;
- Return/refund, Transfer, correction and replacement correlations;
- budget contributions, reports/exports and delivered artifacts;
- attachments, shared object references and retention holds;
- provenance/history projection rows; and
- existing pending operations or administrative migration decisions.

The plan is explanatory, not authorization. Execution re-reads and locks every
dependency and expected revision. If anything changed, it returns a typed stale-
plan conflict and writes no partial domain effects.

Void/replacement requires an exact confirmation token bound to Account, actor,
command, Transaction ID, plan hash, expected revision, reason and expiration.
The server, not UI text, validates the binding. Collection Purchase correction,
paid evidence and Transfer use their story-specific correction commands even if
the generic plan can display their dependencies.

## Conceptual Target Shape

Names are illustrative; responsibilities are the contract.

| Family | Responsibility |
|---|---|
| `transaction_capture_drafts` | Nonfinancial synchronized draft metadata and revision, if cross-device drafts are enabled |
| protected local draft/byte store | Encrypted offline-first draft fields and unuploaded media |
| `transactions` | Canonical posted Purchase/Return identity, scope, type, amount, currency, effective time and current lifecycle projection |
| typed component tables | Item roles, receipt/non-item lines, allocations and story correlations that exactly reconstruct final cents |
| `transaction_lifecycle_events` | Append-only post, metadata correction, void and replacement evidence |
| `transaction_correlations` | Typed original/replacement/refund/collection/migration relationships; never generic semantic edges |
| `migration_review_records` | Raw incomplete/contradictory source evidence, classification and reviewer receipt |
| operation/result rows | Idempotency key, payload hash, expected revisions and durable accepted/rejected/conflict result |

Use `bigint` cents, explicit currency, `timestamptz`, stable client-generated text
IDs, foreign keys for core relationships, checks for legal state/type/amount
combinations, and JSON only for versioned evidence whose shape is genuinely
variable. Index every foreign key. Use partial indexes for active drafts and
posted Transactions and equality-first/keyset indexes for scoped lists. Validate
plans against production-scale staging with `EXPLAIN (ANALYZE, BUFFERS)`; do not
partition without measured need.

## Atomicity and Locking

- Complete external preparation before opening the database transaction.
- Acquire the operation row first, then scope/Transaction headers, referenced
  drafts/Invoices, Items, components/dependencies, lifecycle/correlation rows,
  and projection/result rows in one shared deterministic order.
- Revalidate authorization, evidence profile, component cents, expected
  revisions, enabled reference data and dependency plan while locks are held.
- Append canonical facts, lifecycle evidence, accounting contribution changes,
  projection invalidation/update and operation result atomically.
- Keep the transaction short; perform no media upload, remote parsing, PDF work,
  email or other external call while holding locks.
- Serialization/deadlock retry uses the same operation ID and payload hash.

## Authorization, RLS, and Sync

- Draft read/write requires trusted Account membership and the applicable
  financial capture capability. Canonical post/correction/void uses narrower
  explicit capabilities; source payloads never grant scope.
- Revoke direct canonical table writes from app and MCP roles. Both clients call
  the same handlers and receive the same typed outcomes.
- RLS applies existing-row and resulting-row Account/scope checks and indexes
  every membership/policy key. Private security-definer helpers use fixed/empty
  `search_path`, explicit identity checks, minimal grants, and revoked public
  execution.
- Restricted users do not receive canonical financial rows, draft existence,
  operation-result details, counts, or totals through RLS or Sync Streams.
- Selected Project/Inventory streams include accepted canonical summaries,
  needed components/correlations, operation results and readiness. Pending post
  is visibly pending and cannot be folded into authoritative totals.
- Draft/media/logout cleanup follows the approved local-durability and offline-
  lease policy. Logout cannot silently erase pending post operations or
  unuploaded bytes.

## Migration and Reconciliation

For each source Transaction and related tombstone:

1. retain raw document/tombstone, field presence, type/status/scope/payer,
   amounts, timestamps, Item arrays/back-references, Invoice/lineage/attachment
   links and source hash;
2. classify economic story using all evidence, never the type string alone;
3. import as canonical posted only when the target evidence profile is proven;
4. map incomplete, contradictory, unknown, partial-settlement or ambiguous rows
   to migration review with stable reason codes;
5. preserve canceled/deleted evidence without resurrecting it into active money;
6. map actual opposite money as Purchase/Return and erroneous-posting history as
   lifecycle/correlation evidence;
7. record every source row as mapped, quarantined, approved omission, or
   superseded evidence in the migration journal; and
8. prove repeat/import-resume idempotency and exact source-to-target correlation.

Reconcile counts and hashes by source disposition; cents by Account/scope/type/
currency/category; component reconstruction; active versus voided contribution;
Item/Invoice/Transfer/correction dependencies; attachment retention; and every
review reason. A count of imported rows alone is not reconciliation.

## Required Acceptance Tests

### Posting and draft behavior

- process death and device restart preserve draft fields and unuploaded bytes;
- drafts never affect budgets, Invoices, reports, search totals, or canonical
  Transaction lists;
- same operation/same payload returns one result; same ID/different payload
  conflicts;
- missing scope/type/positive cents/currency/date/component/category/story
  evidence rejects with stable field/reason codes;
- components reconstruct final cents exactly; O-030/O-031 variants fail closed;
- offline post remains visibly pending and nonauthoritative until acceptance;
- stale draft/reference revision rejects without a partial Transaction; and
- app and MCP pass the same posting behavior suite.

### Lifecycle and concurrency

- a never-posted clean draft can be discarded; a posted Transaction cannot be
  physically deleted through app, MCP, direct Data API, or offline replay;
- metadata correction preserves economics and appends before/after/reason;
- replacement atomically voids the original, posts one replacement, and leaves
  net/accounting projections correct;
- actual money returned creates Return rather than a void;
- paid Invoice, Item acquisition, Transfer, attachment hold and prior correction
  dependencies route to their typed command or reject safely;
- stale confirmation/plan/dependency revision fails with no partial effects;
- concurrent post/post, post/discard, post/Invoice collection, void/Return,
  correction/void and attachment-detach races converge to one explainable state;
  and
- serialization/deadlock retry never duplicates lifecycle or contribution rows.

### Security, offline, and migration

- cross-account, restricted-role, forged scope and direct-table attempts cannot
  read or write protected drafts/canonical evidence or infer their existence;
- revocation and logout follow the approved lease/cleanup behavior without
  silently discarding pending work;
- local queries distinguish pending/rejected/synchronized and complete/partial
  readiness after full network loss;
- complete source fixtures post; incomplete/contradictory/deleted/tombstoned
  fixtures receive exact reviewed dispositions without fabricated evidence;
- interrupted and repeated imports produce identical IDs, hashes and results;
  and
- reconstructed target accounting/provenance equals approved source semantics,
  with every difference explicitly classified.

## Approval Consequences

If approved:

1. add confirmed decisions and update the canonical Transaction/offline/migration
   specs before changing architecture status;
2. promote the state/evidence/command/retention contract into architecture
   documents 02/04/05/06/07;
3. remap the 36 affected residual surfaces while retaining O-023/O-030/O-031 and
   other independent blockers;
4. produce reviewed conceptual DDL, RLS, Sync/query profiles, migration fixtures
   and behavior tests; and
5. include offline pending-post and concurrent post/lifecycle cases in the
   A-003/A-004 vertical spike.

If rejected, the replacement must still define when money becomes canonical,
how incomplete capture stays nonfinancial, how posted evidence is retained, and
how every legacy incomplete/deleted/tombstoned row receives an explicit
migration disposition.

## Approval Checklist

- [ ] Draft is durable but nonfinancial.
- [ ] Canonical Purchase/Return requires the approved minimum evidence profile.
- [ ] Offline post remains pending and outside authoritative totals until server
  acceptance.
- [ ] Posted Transactions cannot be physically deleted by ordinary app/MCP.
- [ ] Void is reserved for a proven erroneous posting and remains auditable.
- [ ] Actual opposite money creates a real Purchase/Return.
- [ ] Material correction uses atomic void-and-replacement correlation.
- [ ] Transfer and Invoice collection keep their story-specific handlers.
- [ ] Incomplete source rows enter migration review rather than canonical money.
- [ ] RLS/Sync prevent both writes and existence/aggregate leakage.
- [ ] A-003/A-004/A-015 still require the isolated vertical spike.
