# Architecture Decision Register

Status: active
Architecture version: 0.1
Last reviewed: 2026-08-31

This register records cross-cutting technical decisions. Product behavior remains
in the redesign product decision log. A proposed decision is not an
implementation authorization.

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

**Status:** blocked pending product/security approval.

A disconnected device cannot receive membership revocation. Ledger must define
how long previously synchronized sensitive data remains accessible without a
successful online authorization refresh. The policy must balance job-site
offline use, device theft, membership revocation, and user expectations.

The implementation may not claim immediate offline revocation. Logout and local
account removal must follow the pending-work disposition policy, then clear the
database and encryption key regardless of the lease choice. Explicit destructive
discard is permitted only with the confirmation and cleanup semantics defined in
the offline architecture.

S3/S4 of the
[isolated vertical-spike protocol](../../plans/ledger-accounting-redesign/vertical-spike-protocol.md)
collect enforcement evidence. They cannot choose the lease duration or recovery
copy without explicit product/security approval.

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
