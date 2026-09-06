# Decision Packet — O-007/O-015 Item Accounting and Provenance Model

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Item Accounting, Inventory/Provenance, Invoicing, Budget, Transfer
Unlocks: 49 unique residual surfaces (O-015: 46; O-007: 31; overlap: 28)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject the following combined direction:

> Use explicit relational facts for acquisition, temporal placement, real money,
> Item billing occurrences, Invoice membership/collection, Transfer, and
> correction. Build Item history as a derived, rebuildable projection from those
> facts. Do not extend the current generic `LineageEdge` graph into the target
> accounting authority, and do not keep `item.transactionId` as a polymorphic
> relationship.

O-007 and O-015 should close together. Choosing an occurrence table without the
acquisition/placement/Invoice/Transfer relationships leaves it ambiguous;
choosing those relationships while keeping a generic lineage graph creates two
competing authorities.

This packet proposes the relational contract and tests. It is not DDL,
implementation authorization, production migration authorization, or approval
of Supabase/PowerSync A-003/A-004 before the vertical spike.

## Confirmed Constraints

The design must preserve all of these existing decisions:

- One physical Item has one stable identity through project, Inventory,
  return, resale, Invoice and Transfer cycles (D-018/D-022).
- Transactions mean real Purchase/Return money in the scope whose owner paid or
  received it; Transfer is the only non-cash Transaction exception (D-001/
  D-002).
- A project Item is Accounted For only by a real Client-paid Project Purchase
  relationship or billable Item occurrence. Space and Invoice membership do not
  determine it (D-019/D-023).
- Client-paid Link selects a real current-Project Purchase. Business-paid Link
  creates open demand and no pre-collection Project Transaction (D-020/D-021).
- Whole-Invoice collection creates one actual Project Purchase and freezes the
  exact source revisions/allocations. Moving unpaid value to paid must not
  increase total spend.
- Same-Client Transfer is direct, atomic, paired and client-wide net zero. It
  cannot route through Inventory or cross Client IDs (D-003–D-006/D-017).
- Physical custody, a Client credit, an actual vendor refund, a Client cash
  refund, and an accounting correction are different stories and commands.
- Inventory/project streams must carry enough authorized evidence to explain
  placement and sale/return/resale provenance offline, with explicit completeness.
- Existing Firebase Item/Transaction/lineage/proto shapes are migration evidence,
  not target schema or a reason to build a Firebase adapter.

## Options

### Option A — Extend generic lineage edges

Keep an Item plus a generalized edge table linking Items, Transactions,
Projects and movement kinds. Derive acquisition, placement, billing and history
from the graph.

Advantages:

- closest to the current implementation;
- can represent unusual relationships without schema changes; and
- fewer initial table names.

Costs and risks:

- relationship meaning remains optional and difficult to constrain;
- graph shape can contradict current Item/Transaction arrays;
- RLS and PowerSync must download/interpret a broader graph;
- handler, migration and report code repeatedly infer the same semantics; and
- it preserves the exact ambiguity the redesign is meant to remove.

Recommendation: reject as canonical authority. Retain legacy lineage IDs only
as source correlation and migration evidence.

### Option B — Explicit facts plus derived history (recommended)

Store each business fact in a typed relational family. Build a normalized Item
history projection from those facts for local/MCP reads.

Advantages:

- database constraints match product invariants;
- story commands have clear lock/write sets;
- RLS/Sync can filter financial versus physical evidence precisely;
- migration ambiguity becomes explicit quarantine instead of inferred success;
- repeated sale/return/resale cycles remain explainable; and
- history can be rebuilt without becoming a second writer authority.

Costs and risks:

- more tables and explicit transformations;
- migration must classify overloaded source relationships carefully; and
- projection/readiness design must be proven in the PowerSync spike.

Recommendation: approve.

### Option C — Full event sourcing

Write all state changes to a universal append-only event store and derive every
current table/projection from replay.

Advantages:

- maximal audit history and replay flexibility.

Costs and risks:

- highest operational and developer complexity;
- difficult RLS/Sync payload design;
- more projection/version/rebuild machinery than Ledger currently needs; and
- slower delivery with no demonstrated product requirement for universal replay.

Recommendation: reject. Keep immutable evidence where the domain requires it,
without making every row an event-sourced aggregate.

## Recommended Relational Model

Names are conceptual and may change during reviewed DDL. The responsibilities
and invariants are the decision.

| Family | Authority | Mutable boundary |
|---|---|---|
| `items` | Physical identity and descriptive fields | Normal details/status/bookmark under revision; no polymorphic Transaction field |
| `item_acquisitions` | Actual acquisition evidence and cost/tax basis for an Item | Correct only through typed correction; optional unresolved evidence awaits O-016 |
| `item_placements` | Temporal Inventory/Project placement and optional Space | Exactly one active placement; close old/open new atomically |
| `transactions` | Actual scope-owned Purchase/Return money and evidence | Posted records lock accounting fields; lifecycle awaits O-029/O-032 |
| `transaction_items` | Typed Item participation in actual money evidence | Role distinguishes acquisition from Client-paid Project Purchase; no generic membership array |
| `item_occurrences` | Signed project billing demand/credit for one Item lifecycle | Open revision under trusted commands; frozen/settled versions are immutable |
| `invoice_source_links` | Live created/sent Invoice membership by stable source ID/revision | Lifecycle and sent revision rules await O-034 |
| collected source/allocation rows | Frozen exact source revision, amount, category and collection Purchase | Append-only; corrections add evidence rather than rewrite |
| `transfers` plus paired `transfer_entries` | One same-Client direct Transfer and its source/destination project effects | Exactly one source and one destination entry; original immutable after completion |
| `correction_events` | Typed before/after/reason/actor evidence | Append-only; command changes canonical row in the same transaction |
| Item history projection | Ordered authorized explanation of the facts above | Rebuildable/read-only; never accepted as mutation input |
| operation/result tables | Idempotency, payload hash, pending/applied/rejected/conflict evidence | Server result is durable; retries return the same outcome |

### Item identity and placement

- `items.id` is allocated before connectivity and never changes during Link,
  movement, invoicing or Transfer.
- New target IDs should be time-ordered client-generated text IDs (for example
  ULID/UUIDv7 text); legacy Firebase IDs remain valid through source correlation.
  Do not use random UUIDv4 defaults for high-write indexes.
- `item_placements` is temporal. One partial unique constraint permits at most
  one row with no end time per Item.
- Project placement carries `project_id`; Inventory placement does not invent a
  project. Space is optional and must belong to the active placement scope.
- Placement changes lock the Item and active placement, close the prior row and
  insert the new row in one short transaction.

### Acquisition and real money

- `transactions` does not represent physical movement. Purchase and Return rows
  record real money in the correct Project or Inventory scope.
- `transaction_items` is typed. An Inventory Purchase can be acquisition
  evidence; a Project Purchase can be Client-paid Item evidence. The same join
  is not allowed to mean both without an explicit role and handler validation.
- Business-paid Link may reference an existing Inventory acquisition. If none
  is selected, O-016 decides the unresolved/backfillable representation; the
  handler must never fabricate a vendor Purchase.
- A physical vendor disposition creates custody/provenance evidence first. Only
  money actually received creates a Return.

### Item occurrences

`item_occurrences` is the authority for project Item billing demand, not a
general movement graph.

Required conceptual fields:

- stable occurrence, Account, Item, Project, category and placement IDs;
- `charge` or `credit` kind and signed integer cents;
- basis/source evidence and revision;
- open/invoiced/settled/canceled-or-reversed lifecycle as ultimately constrained
  by the Invoice decisions;
- source occurrence/reversal correlation where a credit reverses prior demand;
- created/updated/frozen actor/time evidence; and
- source-migration correlation/quarantine status outside ordinary app writes.

Rules:

- Business-paid Link creates exactly one positive open occurrence and no Project
  Transaction.
- A Client-paid Link creates a typed link to a real Project Purchase and no
  occurrence.
- One active billable occurrence is allowed for the same Item placement/story;
  resale creates a new occurrence and never reopens paid history.
- Open price changes revise the occurrence and live Invoice source version
  atomically. Settled occurrences and collected allocations are immutable.
- A paid Item returning to Inventory creates a credit occurrence if the product
  story requires Client credit; actual cash settlement remains separate.
- Zero-value occurrences are prohibited. O-005 controls negative display, not
  whether signed credit evidence exists.

### Invoice and collection relationship

- `invoice_source_links` references occurrence/Expense/Fee/approved adjustment
  by typed stable source ID plus expected revision. It does not copy a second
  authoritative amount.
- Collection locks the Invoice, all live source links, their source rows and the
  operation ID in a consistent order; revalidates eligibility/revisions; writes
  one Project Purchase; and appends frozen source/allocation/payment evidence in
  one short transaction.
- The budget contribution identity survives unpaid-to-paid movement. The live
  occurrence contribution ceases and its collected allocation succeeds it under
  one stable economic identity; the collection Purchase face amount is payment
  evidence, not a second spend contribution.

### Transfer

- `transfers` identifies Account, one Client, Item set, operation, actor/time and
  original/reversal correlation.
- `transfer_entries` contains exactly one source and one destination Project
  record with stable IDs, paired by `transfer_id` and equal/opposite contribution
  effects. Each Project can query its own entry as a Transfer record.
- The handler proves source/destination Projects share the exact Client,
  revalidates every Item/placement/live source and locks Items in stable ID order.
- Placement moves directly source Project to destination Project. No Inventory
  intermediate placement or Sale/Purchase pair is written.
- O-002/O-011–O-014 still decide live-Invoice, tag, Space, reversal and later-
  credit edge cases. This model leaves explicit columns/relations for those
  approved outcomes without choosing them here.

## Canonical Item History

The history read model is a projection, not a mutation table. It merges:

- creation and descriptive corrections;
- acquisition evidence;
- placement intervals and Space changes;
- Client-paid Purchase links;
- charge/credit occurrence lifecycle;
- Invoice membership and collection freeze;
- Transfer entries and reversals;
- physical vendor disposition and actual refund links; and
- typed correction events.

Each projected row carries a stable history-row ID, Item ID, event kind,
effective `timestamptz`, stable tie-break ID, authority family/row ID, safe
display fields, financial visibility class and authority/projection version.
The `(effective_at, id)` cursor is deterministic.

The projection may be a SQL view, transactionally maintained table, or
rebuildable materialization chosen after measurement. In every case:

- authoritative handlers write facts, never history rows as business input;
- reconciliation can rebuild and compare the projection;
- Inventory and selected Project streams include the bounded evidence needed
  for offline explanation; and
- an on-demand historical stream exposes explicit completeness/readiness so a
  partial local history is never labeled complete.

## Postgres Shape and Performance Requirements

- Use lowercase unquoted identifiers.
- Use stable client-allocatable text IDs, `bigint` integer cents, `timestamptz`,
  booleans, and explicit text/check constraints or reviewed Postgres enums.
- Use JSON only for versioned operation/frozen evidence payloads whose shape is
  genuinely variable; core relationships use foreign keys.
- Every foreign key used for joins, RLS, delete/dependency preflight or Sync
  predicates has an index; Postgres does not add these automatically.
- Composite indexes put equality keys first and range/cursor keys last, e.g.
  `(account_id, project_id, state, created_at, id)` for bounded project lists.
- Use partial indexes for active placement, open occurrences, live Invoice
  membership and non-tombstoned rows where queries always apply that predicate.
- Use keyset pagination, never deep `OFFSET`, with all order columns in the
  cursor.
- Do not partition initially. Measure production-scale staging plans/retention
  first; the current expected dataset does not justify partition complexity.
- Schema migrations add constraints safely and verify their existence; they do
  not assume unsupported `ADD CONSTRAINT IF NOT EXISTS` syntax.

Initial index families to validate with `EXPLAIN (ANALYZE, BUFFERS)`:

- active placement by `(account_id, item_id)` and scope lists by
  `(account_id, project_id, ended_at, item_id)`;
- occurrences by `(account_id, project_id, state, created_at, id)` and
  `(account_id, item_id, created_at, id)`;
- transaction Items by both `(transaction_id, item_id)` and Item lookup role;
- live Invoice membership unique by source identity and indexed by Invoice;
- collected allocations by Invoice, source identity and collection Purchase;
- Transfer entries by Project/time and Transfer pair;
- operation/result by Account/operation ID and pending age; and
- history projection by `(account_id, item_id, effective_at, id)` and bounded
  Project history cursor.

## Transaction and Locking Contract

Handlers perform validation/external preparation before opening the database
transaction. No media upload, remote fetch or payment/network call occurs while
holding row locks.

Within a command, acquire locks in one deterministic order:

1. operation row/idempotency key;
2. affected Project/Invoice/Transaction headers by stable ID;
3. Items by stable ID;
4. active placements/acquisitions/occurrences/source links by stable ID; and
5. projection/result rows.

The exact order may be refined, but every handler touching the same families
must share it. Prefer set-based statements and short transactions. Serialization
or deadlock retries retain the same operation ID and payload hash.

## RLS, Grants, and Sync

- Revoke default public table/function access. Grant only named query/handler
  entry points to the intended role.
- Enable RLS on every tenant-owned table and index `account_id`, membership and
  relationship columns used by policies.
- Existing-row and resulting-row checks prevent an update from moving data to
  another Account/Project.
- Complex handler authorization may use a private `security definer` helper only
  with explicit caller identity checks, empty `search_path`, explicit grants and
  revoked direct execution from public roles.
- Physical placement may be visible to a member who cannot receive acquisition,
  price, occurrence, Invoice or Transfer amounts. RLS/security-invoker queries
  and Sync Streams enforce that separation before download.
- App and MCP invoke the same commands and visibility-safe query profiles. A
  service credential never substitutes for the human Principal.

Minimum Project stream evidence:

- Items and active placements/Space;
- Client-paid Purchase links;
- open/live/settled Item occurrence summaries allowed by visibility;
- live Invoice source membership and immutable collected allocation references;
- Transfer entries and correction results; and
- operation results and history/readiness version.

Minimum Inventory stream evidence:

- Items and active placement;
- acquisition links/evidence permitted by visibility;
- sale/return/resale-related occurrence/Transfer/correction evidence sufficient
  to explain provenance; and
- operation results and history/readiness version.

## Source Migration Mapping

The transformer starts from an immutable Firebase export and Storage manifest.
It never discovers semantics while writing production target data.

| Source evidence | Target treatment |
|---|---|
| real Item document | one stable target Item plus source correlation |
| Item `transactionId` | classify referenced Transaction and map to acquisition, Client-paid Purchase link, legacy movement evidence or quarantine |
| Transaction Purchase/Return | actual scope-owned money record after type/scope/payer validation |
| `paymentToBusiness` collection | target Project Purchase correlated to Invoice collection; no target legacy type |
| Sale/movement Transaction | placement/occurrence/Transfer/provenance mapping as approved; no target Sale type |
| mutable `itemIds` arrays | validation evidence only; rebuild typed joins and report mismatches |
| LineageEdge | source correlation/validation evidence; map to authoritative fact or quarantine, never silently drop |
| current/live Invoice membership | typed source link with source revision after eligibility reconciliation |
| paid Invoice/settlement evidence | immutable collected source/allocation/payment rows and target Purchase correlation |
| proto Item | O-018/O-019 importer to a real Item or quarantine; no runtime proto table/writer |

Every source Item/Transaction/edge/Invoice reference receives one target mapping,
explicit quarantine, approved omission, or superseded-evidence disposition.
Counts, IDs, relationship hashes, money cents and history readiness reconcile.

## Required Acceptance Tests

### Domain and atomicity

- Client-paid Link creates one typed Purchase relationship and no occurrence.
- Business-paid Link creates one open positive occurrence and no Project
  Transaction; optional acquisition behavior follows O-016 without fabrication.
- Retry with the same operation/payload returns the same result; mismatched
  payload rejects.
- Quantity greater than one remains one Item unless an explicit copy command
  creates distinct physical IDs.
- Unpaid move/remove, paid return credit, actual vendor refund, Client cash
  refund, Transfer and correction each produce only their story-specific facts.
- Whole-Invoice collection freezes exact source revisions, writes one actual
  Project Purchase and moves budget value unpaid to paid without changing total.
- Resale creates new placement/occurrence evidence and never edits frozen paid
  history.
- Same-Client Transfer creates one pair, moves directly, is client-wide net zero
  and rejects cross-Client/inventory destinations atomically.

### Concurrency and failure

- simultaneous Link/link, Link/move, move/collection, Transfer/collection,
  price edit/collection and correction/story commands serialize or return typed
  conflict with no partial facts;
- deterministic lock-order stress produces no unexplained deadlock and safe
  operation retry handles serialization/deadlock errors;
- process/network loss after local acceptance and before/after server commit
  converges to one result; and
- a permanent rejection advances the queue and remains visible without blocking
  unrelated operations.

### Security and offline

- cross-account and resulting-row scope changes fail in RLS and handlers;
- restricted users receive physical placement without protected money/vendor/
  occurrence/Invoice fields or counts;
- Project and Inventory histories are explainable offline when readiness is
  complete and visibly partial otherwise;
- membership revocation removes future download/access and follows the approved
  local lease/cleanup policy; and
- app and MCP pass the same command/query behavior and authorization suites.

### Migration and reconciliation

- every source Item/Transaction/lineage edge/Invoice relationship maps or has an
  explicit reviewed disposition;
- ambiguous `transactionId`, mismatched `itemIds`, missing edges and contradictory
  movement flags quarantine instead of inventing money/provenance;
- repeated import and interruption resume create no duplicate fact/history row;
- history projection rebuild produces the same stable rows/hashes; and
- source/target accounting and provenance differences are zero or individually
  explained by approved semantic mappings.

## Approval Consequences

If approved:

1. update O-007/O-015 in the decision log and traceability table;
2. promote this relationship model into architecture documents 02/04/05/06;
3. map the 49 unique residual surfaces that depend on O-007/O-015, retaining any
   other blockers on the same surfaces;
4. derive reviewed conceptual DDL/RLS/Sync/query contracts and migration
   fixtures; and
5. include this model in the A-003/A-004 vertical spike before provider approval.

If rejected, record which option replaces it and how that option satisfies every
confirmed constraint and acceptance test above. Do not fall back implicitly to
`item.transactionId`, mutable arrays or generic lineage edges.

## Approval Checklist

- [ ] Occurrences are approved as typed Item billing demand/credit, not generic
  lineage.
- [ ] Acquisition and temporal placement are separate authoritative facts.
- [ ] Actual money remains separate from physical movement and billing demand.
- [ ] Invoice live membership and collected freeze are separate relations.
- [ ] Same-Client Transfer uses one aggregate plus exactly two paired entries.
- [ ] History is derived/rebuildable and exposes offline completeness.
- [ ] Correction is typed and append-only in evidence.
- [ ] The migration quarantine rules are acceptable.
- [ ] The RLS/Sync visibility split is acceptable.
- [ ] The vertical spike must prove query plans, lock behavior and offline history
  before A-003/A-004 approval.
