# Architecture Decision Register

Status: active
Architecture version: 0.2
Last reviewed: 2026-09-07

This register records cross-cutting technical decisions. Product behavior remains
in the redesign product decision log. A proposed decision is not an
implementation authorization.

Significant technical changes must be recorded here as they are made (user
instruction, 2026-09-07). State what changed and why, intended behavior/history
preserved, tradeoffs, and links to verification evidence or remaining gaps.
Routine edits need no entry. This register records decisions, not a second
progress tracker; use the existing unified checklist for implementation status.

## Status Definitions

- **accepted** — architecture direction approved in principle;
- **proposed** — recommended, awaiting spike/review or explicit adoption;
- **blocked** — cannot close until a named product or technical decision closes;
- **superseded** — retained for history but no longer the target; and
- **rejected** — considered and deliberately not chosen.

## Decision Summary

| ID | Status | Decision |
|---|---|---|
| A-001 | accepted | Use domain-oriented ports and backend adapters |
| A-002 | accepted | Separate commands from local queries |
| A-003 | proposed | Supabase Postgres becomes target server authority |
| A-004 | proposed | PowerSync SQLite becomes the target local data plane |
| A-005 | proposed | Complex mutations use durable idempotent operation envelopes |
| A-006 | proposed | Structured sync excludes attachment bytes |
| A-007 | proposed | Choose Supabase Auth at launch or a temporary Firebase Auth integration |
| A-008 | proposed | Do not use permanent or general-purpose dual writing |
| A-009 | proposed | Use expand–migrate–switch–contract |
| A-010 | proposed | Use internal principals independent of auth-provider subjects |
| A-011 | proposed | Encrypt the local PowerSync database with a Keychain-held key |
| A-012 | superseded | Do not implement the former Firebase-adapter proposal |
| A-013 | proposed | Mirror authorization in RLS and Sync Streams |
| A-014 | accepted | Backend SDK types are infrastructure-only |
| A-015 | blocked | Choose the optimistic projection mechanism for complex offline commands |
| A-016 | blocked | Approve the bounded offline-access lease |
| A-017 | accepted | Firebase is a migration source, not a redesigned application adapter |
| A-018 | accepted | Use one fail-closed OperationID ownership inventory across local command families |
| A-019 | accepted | Improve Item relationship storage while preserving meaning and useful history |
| A-020 | accepted | Persist imported client payments atomically with immutable source bytes |

## A-001 — Domain-Oriented Ports and Backend Adapters

**Decision:** Views and application use cases depend on Ledger-specific ports.
Supabase/PowerSync is the initial production implementation; test adapters and
any future replacement conform to the same ports.

**Reason:** The current protocols still expose Firebase listeners, dynamic field
maps, paths, and write batches. Those types make a backend replacement spread
through the application.

**Consequences:**

- domain/application modules contain no vendor SDK imports;
- mapping code is explicit;
- adapter construction is centralized; and
- adding a backend requires behavioral contract conformance.

**Rejected alternative:** A generic CRUD repository shared by all layers. It
hides business atomicity and collapses different consistency semantics into a
misleading interface.

## A-002 — Command/Query Separation

**Decision:** Mutations are typed domain operations. Reads are local query ports
returning read models and streams.

**Reason:** Ledger requires local reactive reads but server-authoritative
multi-record writes. One repository interface cannot express both honestly.

**Consequences:** Read models may be denormalized and screen-specific. Commands
may be implemented with different backend mechanics while preserving the same
receipt and result lifecycle.

## A-003 — Supabase Postgres as Target Authority

**Decision:** Subject to the vertical spike, Postgres is the canonical target
for structured Ledger data and accounting invariants.

**Reason:** Relational constraints, transactions, functions, joins, audit
queries, and explicit migrations match the redesigned accounting model.

**Evidence required:** RLS performance, command latency, migration rehearsal,
backup/restore, and current-account capacity tests.

**Evidence protocol:** Run S0/S1/S8/S9 and the mandatory DB/RLS/restore/
performance/cost tests in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

**Consequence:** This does not make the Supabase client library part of the
domain. Postgres is replaceable behind ports and exported data contracts.

## A-004 — PowerSync as Target Local Data Plane

**Decision:** Subject to the vertical spike, PowerSync supplies encrypted local
SQLite, reactive queries, partial synchronization, and durable uploads.

**Reason:** Plain Supabase client calls do not provide Ledger's required durable
offline database and upload queue.

**Evidence required:** Seven-day offline behavior, app termination, auth refresh,
conflict handling, revocation, cold sync, storage footprint, and cost metrics.

**Evidence protocol:** Run S0/S3–S9 and every mandatory local/sync/offline/media/
evolution/physical/cost test in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

**Consequence:** Supabase Realtime is not used for rows already synchronized by
PowerSync. Realtime may be considered separately for ephemeral presence only.

## A-005 — Durable Idempotent Operation Envelopes

**Decision:** Complex operations have an operation ID, contract version, actor,
scope, payload, creation time, preconditions, and observable result.

**Reason:** Offline queues and network retries provide at-least-once delivery.
Accounting effects require exactly-once observable outcomes.

**Consequence:** The server stores operation results and returns the prior result
for a repeated idempotency key. A validation rejection is a durable domain
result, not a transport failure that stalls the queue.

## A-006 — Attachment Bytes Outside Structured Sync

**Decision:** PowerSync synchronizes target attachment metadata and canonical
object paths only. A separate durable media queue uploads bytes.

**Reason:** Binary data would inflate sync cost, local databases, and initial
sync time. Object storage supports purpose-built upload and delivery behavior.

**Consequence:** A parent entity and attachment can be locally visible before
the object upload completes. Object upload and metadata reconciliation require
their own idempotency and failure state.

## A-007 — Target Authentication Choice

**Proposal:** Either migrate to Supabase Auth for the target launch or keep
Firebase Auth temporarily through Supabase Third-Party Auth and PowerSync token
validation, then migrate identity as a separate release. The vertical spike and
release-risk review must close this choice.

**Reason:** Supabase and PowerSync can validate Firebase-issued JWTs, which may
lower simultaneous cutover risk, while migrating to Supabase Auth at launch
would remove a legacy dependency earlier.

**Consequence:** Ledger uses an internal principal ID and an issuer/subject
identity mapping so a later Auth migration does not rewrite domain ownership.
The temporary identity integration, if selected, does not require a Firestore,
Firebase Storage, or Firebase application-data adapter.

**Evidence protocol:** S2 compares Supabase Auth with an isolated identity-only
Firebase contingency under the same disqualifying security tests and weighted
migration/recovery criteria. No provider is selected by the protocol itself.

## A-008 — No General-Purpose Dual Writing

**Decision:** Do not make clients permanently write Firebase and Supabase for
the same business operation.

**Reason:** Two offline queues can apply in different orders, reject differently,
and make authority ambiguous.

**Allowed exceptions:** Read-only shadow calculations and deterministic
migration correlation. Neither exception is an application dual writer.

## A-009 — Expand–Migrate–Switch–Contract

**Decision:** Additive structures precede data migration; authority switches
only after reconciliation; destructive cleanup follows the rollback window.

**Reason:** Old clients and offline pending writes cannot safely consume a
destructive in-place change.

## A-010 — Provider-Independent Principals

**Decision:** Domain membership references a Ledger principal, not a Firebase UID
or Supabase Auth UUID directly.

**Reason:** Authentication providers issue different subject formats and may
change. Membership and audit identity must remain stable.

**Evidence required:** RLS helper and PowerSync Sync Stream join performance.

## A-011 — Encrypted Local Database

**Decision:** Encrypt the local structured database and store its key in the
platform Keychain.

**Reason:** Offline operation places account and financial data on the device.

**Consequence:** Key creation, rotation, pending-work disposition before logout
deletion, restore behavior, and multi-account storage are explicit lifecycle
responsibilities. Routine logout cannot silently destroy queued operations or
unuploaded media.

## A-012 — Superseded Firebase-Adapter Proposal

**Status:** superseded by A-017. Do not implement.

**Original proposal:** Wrap current Firebase behavior behind the new ports
before replacing it.

## A-013 — RLS and Sync Stream Authorization Symmetry

**Decision:** RLS authorizes writes and direct API reads. Sync Streams separately
authorize downloads. Both derive access from the same principal/membership and
financial-access facts.

**Reason:** PowerSync download rules do not authorize uploaded changes, and RLS
alone does not prevent the sync service from downloading rows selected by an
over-broad stream.

**Consequence:** Every access-control change has paired RLS and Sync Stream tests.

## A-014 — SDK Types Are Infrastructure-Only

**Decision:** Vendor timestamps, user objects, snapshots, rows, errors, storage
references, listeners, and upload entries are mapped before crossing a port.

**Reason:** SDK types are the most common source of accidental infrastructure
coupling.

## A-015 — Complex-Command Optimistic Projection

**Status:** blocked pending vertical spike.

The chosen implementation must satisfy all of these semantics:

- one local atomic acceptance;
- durable survival across restart;
- immediate useful UI projection;
- one server command and one idempotency key;
- clean rollback/reconciliation on rejection; and
- no stuck global upload queue for a permanent validation failure.

Candidates are a pending-operation overlay, tagged optimistic row mutations, or
a hybrid. The spike must compare query complexity, PowerSync upload grouping,
rollback behavior, and cross-screen consistency before this decision closes.
The exact S5 fixtures and hard failures are defined in the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md).

## A-016 — Offline-Access Lease

**Status:** no-expiry, device-unlock and learned Account-removal behavior approved on 2026-09-07; financial access reduction and recovery procedure remain open.

A disconnected device cannot receive membership revocation. The user chose no
offline time limit for previously downloaded work and the device's normal
unlock with no additional Ledger biometric/passcode/PIN prompt. Do not add a
finite authorization lease or treat provider-token expiry as local-data expiry.
This choice does not authorize new downloads or override revocation learned
online. On learned Account removal, immediately lock normal Account reads/edits
and stop uploads under the removed Principal's permissions. Retain unsynced
operations and media encrypted for a separately approved recovery process; no
automatic upload, export, reassignment or recovery access is implied. These
approved rules can be implemented without choosing a recovery procedure.
Financial scope reduction short of Account removal and the recovery procedure
remain open under O-058; full hosted activation/security readiness is not proved
by this product decision.

The implementation may not claim immediate offline revocation. Logout and local
account removal must follow the pending-work disposition policy, then clear the
database and encryption key regardless of the lease choice. Explicit destructive
discard is permitted only with the confirmation and cleanup semantics defined in
the offline architecture.

S3/S4 of the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md)
collect enforcement evidence. They must honor the approved no-expiry/device-unlock
choices and cannot decide remaining recovery policy or copy without approval.

## A-017 — Firebase Is a Migration Source Only

**Decision:** Leave the released Firebase application operational and
substantially untouched while the Supabase/PowerSync app is built and tested in
isolation. Firebase-specific work is limited to read-only export, migration
mapping, final pending-write disposition, write freeze, backup, and retained
rollback evidence. No Firebase repository, listener, writer, Function, rule, or
Storage implementation is made to conform to the redesigned application ports.

**Reason:** A Firebase adapter would be throwaway implementation work and would
risk implementing the redesign twice. Target port contracts are proven by the
Supabase/PowerSync implementation and deterministic test adapters.

**Consequence:** The cutover is a rehearsed data migration plus authority
switch. The old Firebase binary may continue to exist on devices, but the frozen
Firebase backend rejects post-cutover writes and the new app uses only the target
data implementation.

## A-018 — One Fail-Closed Local OperationID Ownership Inventory

**Decision:** `OperationID` is one global idempotency namespace, not a namespace
per Account, device, payload, or command family. Within one encrypted Account
database, `local_operations.id` is the normal ownership claim and every
operation-bearing local relation participates in one centralized integrity
inventory before any command admission or replay.

**Reason:** An insert-only command view's `ps_crud` entry, synchronized result,
forbidden local result-table queue mutation, pending projection, or overlay can
outlive or become detached from the generic operation
row. Checking only one family view or only the generic row allows malformed
evidence to be silently rebound to another family and makes later replay,
upload, and reconciliation ambiguous. The pinned PowerSync insert-only trigger
writes the queue entry without persisting a second backing command row, so the
inventory follows that actual storage contract.

**Consequences:**

- one typed same-family owner may proceed only to state-aware exact provider
  validation; a terminal row may stand alone only where that family's existing
  lifecycle drains auxiliary evidence, while incomplete nonterminal or untyped
  rows fail closed and no new cleanup is implied;
- a different family or changed payload returns a stable mismatch;
- orphaned, malformed, ambiguous, or multi-family evidence reserves the ID and
  fails closed without repair or deletion;
- claim, inspection, and family writes share one serialized local transaction;
- schema/source controls reject an unregistered operation-bearing relation or
  accepting provider; and
- local enforcement covers one physical Account database, while globally unique
  generation and the authoritative server result key cover separate devices.

This decision adds no second local registry table and chooses no cleanup or
retention behavior. It does not advance A-003, A-004, A-015, A-016, hosted
resources, migration execution, or production authority.

## A-019 — Preserve Meaning, Improve Item Relationship Storage

**Decision:** D-028 permits replacing legacy structures where a concrete
correctness, simplicity or maintainability benefit exists. Acquisition,
placement, billing and payment use explicit relationships; history is read from
those facts rather than a second competing accounting authority. Existing
Transaction links and lineage already represent important history. They are
source evidence to preserve and reconcile, not missing functionality or a reason
to discard relationships.

**Reason/tradeoff:** Explicit relationships support database constraints and the
confirmed accounting redesign, but require careful migration and may need more
tables. Prefer shared existing contracts; avoid a universal event store or
speculative generality. Improve concrete table details during implementation.

**Preservation and evidence:** The existing
[Item relationship note](../../plans/ledger-accounting-redesign/decision-packets/O-007-O-015-item-accounting-and-provenance.md#verified-source-relationships)
records inspected source fields, settlement links and lineage writers. Preserve
stable Item identity, historical amounts and relationships, original source
correlation and unresolved evidence. It is source inspection, not proof of a
completed target or migration. Target cycle/readback/reconciliation tests remain
required in the unified checklist's `accounting-relationship-provenance` and
`item-cycle-provenance` outcomes. Financial policy, information loss and
production/hosted actions retain their separate approval boundaries.

**Source reconciliation boundary:** Resolve historical links from exact
`accounts/{account}/items|transactions|projects/{id}` paths, not current Item
membership or exporter classification labels. Preserve every input document;
duplicate, malformed or foreign-Account records cannot satisfy references.
Lineage document faults also prevent that edge from advancing to semantic
mapping. This deliberately quarantines uncertain history instead of choosing a
plausible relationship. `FirebaseLineageSourceReview` connects these checks to
the existing validated fixture reader; source-shaped cycle tests are separate
from the frozen v1 fixture, whose simplified movements do not prove shipped
lineage coverage. Neither structural reconciliation nor a `returned` label
establishes a client refund, paid occurrence or completed target import.

**Explicit client-payment translation:** A legacy `paymentToBusiness` record
means actual client payment (`InvoiceService.markCollected` writes category-specific
payment records). Under D-001/D-002 it maps to the target Project Purchase
classification, retaining its exact integer cents and entire source document.
Do not merge historical payments or infer full Invoice settlement from this
classification; the source can represent partial or category-level collection.
`FirebaseClientPaymentConversion` requires a reconciled source→target Project
scope supplied by the migration caller. Other source transaction types, unclear
payers, nonpositive amounts and non-integer money remain unresolved here. This
is a domain transform, not the completed scope-mapping/import pipeline or proof
that historical Invoice allocations reconcile.

`FirebaseClientPaymentBatch` binds that transform to an exact source Project
snapshot and an explicit target Project/Client assignment, plus stable supplied
Transaction IDs. The source has only `clientName`; equal names never establish
ownership. Duplicate source paths/target identities, changed or missing Project
evidence and sum overflow prevent affected payments or totals from reconciling.
The batch retains one result per input and does not merge category payments.
Mappings may cover a larger import plan: unused entries create no payment and
are not approved by a successful subset. Import approval, complete export
coverage, target persistence and final settlement reconciliation remain separate
requirements.

## A-020 — Imported Client Payment Storage

**Decision:** Begin canonical `spike_transactions` storage with the verified
imported Project Purchase path. Atomically insert its exact integer amount,
explicit currency and Account/Project/Client identity with one private source
record. Composite foreign keys enforce the existing Project's Client and Account.
The source is stored as bytes with a database-derived digest: tagged Firebase
values, NULs and unknown fields must not be coerced into lossy PostgreSQL JSON.

**Retry and retention:** Stable target identity and unique source Account/document
identity prevent duplicate money. An identical retry succeeds; different amounts,
scopes, currency or source bytes conflict and roll back the entire call. Updates,
deletes and truncation of these imported records are rejected. Future approved
corrections must preserve original evidence instead of rewriting history.

**Security/tradeoff:** The import function uses invoker rights in `ledger_private`.
No app/API role, including `service_role`, receives function or table privileges;
both tables enforce RLS. This deliberately leaves app/PowerSync financial reads
unavailable until the relevant policy is resolved. Import-run authorization is a
separate requirement, not something inferred from this SQL primitive. Current
execution requires a trusted operator with direct privileges and RLS bypass;
granting function execution alone is neither sufficient nor a restricted writer
boundary. Any dedicated migration role needs separate security review. The row
immutability trigger is conditional on imported origin so future ordinary
Transaction behavior is not inadvertently frozen.
Current database constraints support only this implemented payment path; normal writes,
Return/Transfer and additional Transaction behavior are not claimed complete.

**Evidence and remaining work:** Local migration `20260907233804` and
`supabase/tests/imported_client_payment_storage.test.sql` verify atomic conflict
rollback, exact cents/source bytes, retry, tenant/Client integrity, immutability
and denied API access. `scripts/test-local-imported-payment-concurrency.mjs`
observes actual lock waits for identical and conflicting concurrent imports and
checks committed results from new database sessions. A shared synthetic parameter
fixture connects the real Swift batch exporter to SQL, preserving cents beyond
JavaScript's safe integer range and the complete tagged source envelope as bytes.
This proves the serialization boundary, not an operational import runner.
Process/database restart recovery, migration-run journals, complete settlement
allocations and hosted verification remain required. No production access or
cutover is authorized.
Grants and RLS follow the current
[Supabase security guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).
