# Verification, Observability, and Operations

Status: proposed architecture
Architecture version: 0.1
Last reviewed: 2026-08-31

## Purpose

Offline-first correctness cannot be established by compiling or by testing one
happy-path server request. This document defines evidence required to trust the
domain, adapters, synchronization, security, migrations, and production system.

## Test Architecture

### Pure domain tests

Fast deterministic tests cover:

- Money, signs, category allocation, and rounding;
- command validation and precondition classification;
- accounting-state projections;
- budget segment calculations;
- Invoice/Transfer/Item lifecycle state machines;
- conflict and correction rules; and
- deterministic migration mappings.

Use fixed clocks and IDs. Domain tests import no Firebase, Supabase, or
PowerSync modules.

### Property and invariant tests

Generate sequences of create, Link, price edit, Invoice, collect, return,
Transfer, correct, and retry operations. Assert continuously:

- no duplicate financial contribution;
- collection does not change combined recognized total;
- same-Client Transfer is net-zero across the Client's projects;
- one Item identity persists;
- paid membership remains immutable;
- idempotent replay does not change results; and
- cross-account relationships never appear.

### Application use-case tests

Use in-memory/failure adapters to verify:

- local receipt versus authoritative result UX;
- queue/rejection/conflict presentation;
- navigation after local durability;
- required-update and maintenance behavior;
- attachment pending/retry behavior; and
- cancellation and context switching.

### Adapter contract tests

Run the contract suites defined in the ports/adapters document against:

- local Supabase/PowerSync target adapter;
- cloud staging target adapter for real-network behaviors; and
- the in-memory reference adapter.

Firebase export/transform fixtures run in the migration suite below, not the
application adapter suite.

### Database tests

For every Postgres migration/function:

- constraints and foreign keys;
- command atomicity and idempotency;
- payload-hash mismatch rejection;
- revision/precondition conflicts;
- concurrent command ordering/deadlock behavior;
- RLS positive/negative matrix;
- grants and function execute privileges;
- view security-invoker behavior;
- trigger/function replay; and
- rollback/forward migration behavior.

Run Supabase security and performance advisors and resolve or explicitly review
every finding.

### Sync tests

Verify:

- authorized account bootstrap;
- project/inventory subscription start, stop, and switching;
- no unauthorized or hidden financial rows in the local database;
- entitlement removal after reconnect;
- large initial sync and incremental sync;
- schema change with old/new clients;
- durable upload across process/device restart;
- permanent rejection without queue starvation;
- transient retry and lost-response idempotency;
- duplicate and out-of-order delivery; and
- clean logout with no pending work;
- logout with queued operations or unuploaded media blocks destructive cleanup;
- sync-then-logout waits for authoritative/resolved outcomes;
- explicit discard names exact counts and removes queue, media, database, and
  key only after destructive confirmation; and
- interruption during logout cleanup resumes fail-closed.

### Migration tests

- deterministic fixture transforms;
- full snapshot dry-run/apply/reapply;
- batch-boundary interruption and resume;
- source-to-target coverage;
- financial/source reconciliation;
- attachment inventory reconciliation;
- ambiguous record blocker reporting;
- production destination refusal; and
- target reset without touching source.

## Required End-to-End Stories

At minimum:

- first sign-in and account discovery;
- reopen previously synchronized account fully offline;
- minimum-field Item creation and later continuation;
- Client-paid and Business-paid Link;
- inventory acquisition and vendor Return;
- inventory Item history remains explainable offline across
  inventory↔project sale/return/resale cycles, with incomplete history labeled;
- open Item charge repricing;
- live Invoice membership edit;
- whole-Invoice collection with lost response/retry;
- pre-Invoice, live-Invoice, and paid Item return;
- same-Client Transfer and cross-Client rejection;
- Transfer/collection concurrency;
- correction/reversal with immutable evidence;
- member financial visibility full/limited/none;
- member revocation while device is offline;
- attachment capture, termination, reconnect, resume, and verified display;
- unsupported client contract and maintenance mode;
- MCP execution of the same command as the app; and
- migrated production-like project reports matching reconciled source evidence.

## Fault Matrix

| Fault | Expected outcome |
|---|---|
| Network absent at command submission | Local durable queued receipt; useful optimistic UI |
| App killed after local acceptance | Command and local projection recover on restart |
| Token expired before upload | Refresh; retain queue; no duplicate command |
| Membership revoked before upload | Durable rejected outcome; no server mutation |
| Server commits, response lost | Retry returns prior result by operation ID |
| Permanent validation failure | Rejected result; later queue entries continue |
| Database unavailable | Queue retained with transient health state |
| Two devices move same Item | One commits; other rebases/rejects explicitly |
| Logout requested with pending work | No deletion; show cancel, sync, and explicit-discard choices with exact counts |
| Explicit discard confirmed | Pending queue/media/database/key are removed; UI never reports server application |
| App killed during logout cleanup | Cleanup resumes fail-closed; old principal data is not reopened half-cleaned |
| Old command contract arrives | Stable update-required rejection/quarantine |
| Sync Stream misconfiguration | Security test fails before deploy; alert on unexpected local row |
| Attachment upload interrupted | Resume/retry same attachment ID/path without duplicate metadata |
| Migration interrupted | Journaled resume; no duplicated target evidence |

## Reconciliation as a Product Safety System

Reconciliation is permanent, not a one-time migration script. It compares
canonical evidence with derived projections and reports zero or explained
differences.

Required recurring checks:

- project/client/account source totals;
- open Invoicing versus Invoice membership;
- collected Invoice allocations versus Purchase and paid snapshot;
- Item placement versus active lifecycle evidence;
- Transfer source/destination pair and net-zero amount;
- operation result versus affected entity revisions;
- projection totals versus source rows;
- attachment record versus Storage object; and
- authorized visibility projection versus permission records.

Every difference includes account/project/source IDs, expected/actual amounts,
rule version, first-seen time, and resolution status. Never log private notes or
media unnecessarily.

## Observability Model

### Client metrics

- app/build/backend/contract/schema versions;
- local database open and query latency;
- active subscription readiness;
- last completed sync and current sync lag;
- pending command count and oldest age;
- rejected/conflicted command count by safe code;
- attachment pending/failed count and oldest age;
- auth refresh failure;
- local decode/mapping failure;
- local database size; and
- offline session duration.

### Server metrics

- command count, latency, outcome, and retry/deduplication rate;
- transient versus permanent failure rate;
- lock wait/deadlock/serialization retry;
- RLS denial and suspicious cross-scope attempt rate;
- migration/reconciliation drift;
- Postgres CPU, connections, disk, I/O, and slow queries;
- Storage upload/download/delete errors;
- Edge Function/external integration failures; and
- MCP command/read activity by tool and outcome.

### PowerSync metrics

- replication lag;
- active/peak clients;
- hosted data;
- synchronized bytes per month;
- bucket/stream count per user;
- initial and incremental sync duration;
- upload queue errors and oldest pending age; and
- reprocessing/deployment state.

## Logging and Correlation

One correlation chain joins:

```text
client session -> operation ID -> server command -> database transaction/result
               -> sync checkpoint -> client reconciliation
```

Logs include environment, build, contract/schema version, safe tenant/entity
IDs, operation ID, and outcome code. They do not include access tokens, service
keys, signed URLs, full notes, media, or unnecessary command payloads.

Migration logs additionally include run manifest and source correlation IDs.

## Initial Service Objectives

Exact numeric latency/volume thresholds are approved after the vertical spike.
The following objectives are normative now:

- **Durability:** zero silently lost locally accepted operations in fault
  testing; destructive loss occurs only after the exact pending counts and
  consequences receive explicit user confirmation.
- **Idempotency:** zero duplicate authoritative financial effects under replay.
- **Integrity:** zero unexplained reconciliation differences at cutover.
- **Isolation:** zero unauthorized rows present in the local database for the
  tested access matrix.
- **Queue health:** permanent domain rejection never blocks unrelated uploads.
- **Offline availability:** cached core workflows remain usable for the approved
  offline-access lease.
- **Recovery:** every alert has an owner and runbook before production cutover.

The spike must establish numeric p50/p95/p99 budgets for local queries, command
application, sync, and attachment upload using production-scale fixtures and
physical devices.

## Alerts

Page or high-urgency alert candidates:

- sustained inability to apply commands;
- replication halted or lag beyond the approved threshold;
- invariant/reconciliation drift involving money or paid history;
- cross-tenant authorization anomaly;
- migration production guard violation; and
- target database/storage outage during cutover.

Ticket or lower-urgency candidates:

- growing queue age for a subset of clients;
- repeated rejected stale commands;
- increased decode/mapping failures;
- rising hosted/synchronized data cost;
- orphan attachments; and
- slow query or RLS regression.

Alerts use rate limits and grouping so one offline device does not create noise.

## Operational Runbooks

Required before production:

- sync/replication lag diagnosis;
- stuck upload queue and poison-operation recovery;
- command idempotency/payload mismatch investigation;
- membership revocation and local data removal verification;
- RLS/Sync Stream access incident;
- Postgres restore and PowerSync resynchronization;
- Storage missing/orphaned object recovery;
- migration abort/resume/rollback;
- accounting maintenance-mode enable/disable;
- unsupported client/stale writer handling;
- reconciliation drift triage and correction; and
- credential/key compromise rotation.

Each runbook names detection, impact, first safe action, evidence to preserve,
rollback boundary, escalation owner, and verification of recovery.

## CI/CD Gates

Every pull request touching architecture-sensitive areas runs the relevant set:

- pure domain and application tests;
- adapter contracts;
- local database/query tests;
- Postgres migration/function tests;
- RLS and Sync Stream security tests;
- schema/config validation;
- Supabase advisors;
- migration dry-run fixtures;
- package-lock/resolved dependency review; and
- documentation decision/register consistency check.

Environment deployment order:

1. local validation;
2. isolated cloud staging;
3. migration rehearsal and physical-device acceptance;
4. explicit production approval; and
5. post-deploy reconciliation and monitoring.

Schema, Sync Streams, command handlers, app, and MCP versions are recorded in a
deployment manifest. Deploying code does not automatically activate its
authority flag.

## Definition of Done for a Vertical Slice

A redesigned feature is complete only when:

- its machine-readable implementation-slice dossier traces exact authority
  sections and invariants to every contract/test/evidence obligation and passes
  the status gate in the redesign conversion control plane's
  `vertical-slice-implementation-method.md`;
- its capability dossier proves which current outcomes are preserved and which
  defects/mechanics are deliberately corrected, improved, redesigned, or
  retired;
- product decisions and invariants are documented;
- domain values/commands/results exist without vendor types;
- local read model and offline behavior exist;
- Firebase source export/migration mapping and cutover freeze behavior are
  documented outside the target application;
- target Postgres schema and handler are atomic/idempotent;
- RLS and Sync Streams enforce the access matrix;
- app and MCP use the same command contract;
- migration mapping and reconciliation exist;
- adapter, fault, security, and end-to-end tests pass;
- metrics, alerts, and runbook changes are complete; and
- rollout/rollback gates are recorded.

Compilation, a successful happy-path simulator run, or a passing server unit
test alone is not definition of done.
