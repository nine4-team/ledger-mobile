# Supabase/PowerSync Isolated Vertical Spike Protocol

Status: executable protocol; execution and provider approval not yet authorized
Created: 2026-08-31
Last reviewed: 2026-08-31
Program: [Ledger Accounting Redesign](README.md)
Architecture decisions: [Architecture Decision Register](../../architecture/redesign/architecture-decisions.md)
Environment plan: [Isolated Pre-Cutover Testing Plan](pre-cutover-testing-plan.md)

## Outcome

This protocol turns A-003, A-004, A-007, A-015, A-016, and physical-target
verification into a reproducible technical decision. A successful run proves
that one real Swift build can use Supabase/Postgres and PowerSync as Ledger's
isolated target while preserving offline durability, tenant isolation,
accounting idempotency, explainable local history, media recovery, and acceptable
performance/cost at Ledger-shaped scale.

The protocol is evidence collection, not a production migration or automatic
architecture approval. A-003/A-004 remain proposed until every mandatory test
passes and the decision register records the reviewed result. A-016 always also
requires an explicit product/security policy decision.

## Non-Goals and Safety Boundary

The spike must not:

- read or mutate production Firebase, Supabase, PowerSync, Storage, Auth, or
  production user identities;
- add a Firebase application adapter, Firestore v2 schema, Firebase Functions,
  rules, indexes, or dual writer;
- treat disposable `spike_*` tables, fields, functions, or Sync definitions as
  approved target DDL;
- import real client names, notes, addresses, receipt images, tokens, or other
  production content;
- approve any product decision packet by encoding its recommendation; or
- deploy, migrate, release, cut over, or enable a production writer.

The existing Firebase application remains untouched. If the Firebase Auth
candidate is tested, it uses an isolated test Firebase Auth project and only
issues identity tokens; it grants no Firestore or Firebase Storage access.

## Decision Closure Matrix

| Gate | Spike question | Required outcome |
|---|---|---|
| A-003 | Can Postgres enforce Ledger-shaped tenant, relational, exact-cent, idempotency, concurrency, RLS, backup and restore requirements at measured scale? | All database/security/restore tests pass with reviewed plans and no unexplained invariant drift |
| A-004 | Can PowerSync provide encrypted, bounded, responsive local data and durable upload/recovery on supported Apple targets at acceptable run-rate? | All local/sync/offline/evolution/performance/cost tests pass |
| A-007 | Is launch safer with Supabase Auth or temporary Firebase third-party Auth? | One option wins the scored migration, recovery, security, offline, complexity and retirement comparison; internal Principal identity remains stable |
| A-015 | Which complex-operation projection is correct and maintainable? | Overlay, tagged optimistic rows, and hybrid are compared against the same fixtures; one passes all semantics with the lowest justified complexity |
| A-016 | What can technology enforce for disconnected access and cleanup? | Lease/unlock/revocation/cleanup behavior is measured; product/security then approves duration and recovery copy |
| Physical verification | Does the real app survive termination, device lock, network loss, storage pressure and reconnect? | Mandatory physical-device matrix passes; simulator-only evidence is insufficient |

Product blockers remain separate. The spike may use fixed synthetic behavior to
exercise infrastructure, but that fixture cannot close O-002–O-039.

## Prerequisites

Execution starts only when all are true:

- an organization-owned disposable Supabase project, PowerSync instance,
  Storage bucket, test identities, and observability destination exist;
- every credential is staging-only and cannot write a production resource;
- the staging app has a distinct bundle ID/container/keychain namespace,
  unmistakable banner, compiled allowlist, and startup refusal for every known
  production identifier;
- exact Supabase Swift, PowerSync Swift, Postgres, CLI, Xcode, iOS, and macOS
  versions are pinned in the run manifest;
- provider documentation and pricing are rechecked on the run date;
- synthetic fixtures and fault controls are reproducible from source; and
- cleanup owner, maximum spend, end time, and resource-destruction procedure are
  approved before any hosted resource is created.

If any resolved endpoint, issuer, project, bucket, database, or identity belongs
to production, the harness must refuse startup before authentication or network
I/O and record `isolation_refused` without printing secrets.

## Thin Vertical Slice

Use a deliberately disposable `spike_*` model sufficient to exercise the
architecture, not to pre-implement the redesign:

- Principal, provider identity, Account, membership, role and financial-access
  facts;
- Client, Project, Space and Item summary rows;
- Item acquisition, current placement, accounting occurrence and derived
  history facts sufficient for repeated inventory→project→inventory→project;
- one paired same-Client Transfer-shaped command using only confirmed D-003–
  D-005/D-017 semantics and fixed synthetic handling for unresolved edges;
- durable operation envelope/result/rejection rows;
- attachment metadata plus a separate protected local-byte/upload queue; and
- version/readiness facts for local queries and schema evolution.

The slice must traverse the real layers:

```text
Swift UI/use case
  -> backend-neutral command/query ports
  -> encrypted PowerSync SQLite and durable local operation state
  -> upload connector / trusted target handler
  -> Postgres transaction, constraints and RLS
  -> PowerSync authorized download
  -> reactive Swift read model and authoritative operation result
```

App and a minimal test MCP client invoke the same trusted command/result
contract. Direct table mutation is not an alternative command path.

## Synthetic Scale Envelope

The reported account shape is roughly ten Projects with 600–700 Items each.
Use synthetic data with no copied business content:

| Dataset | Purpose | Minimum shape |
|---|---|---|
| `tiny` | deterministic correctness/fault tests | 2 Accounts, 3 users, 4 Projects, 40 Items, complete edge stories |
| `ledger_baseline` | reported-scale performance and storage | 2 Accounts; primary Account with 10 Projects and 7,000 Items; 25,000 occurrence/history facts; 2,000 money records; 500 Invoices/revisions; 25,000 attachment metadata rows; secondary Account for isolation |
| `ledger_headroom` | capacity/regression warning | 20 Projects, 20,000 Items and at least 3× baseline relationship/history rows |

The media-byte suite uses a bounded generated corpus rather than 25,000 real
images: small/typical/large valid files, invalid MIME/content, interrupted
multipart upload, duplicate hash, missing local byte, and storage-pressure
fixtures. Record byte distributions and extrapolate separately; never pretend
metadata-only scale proves image transfer cost.

Fixture generation records seed, schema/contract version, exact row/byte counts,
checksums, expected invariant totals, and expected authorized row sets.

## Candidate Comparisons

### Authentication (A-007)

Compare:

1. **Supabase Auth at target launch** — default candidate because it removes the
   legacy identity dependency and keeps the target consolidated.
2. **Temporary Firebase Auth integration** — contingency candidate only if it
   materially reduces launch migration/recovery risk. It is identity-only and
   cannot introduce Firebase application-data access.

Both use immutable internal Principal IDs and provider `(issuer, subject)`
mappings. Score each before choosing:

| Dimension | Weight |
|---|---:|
| Existing-user migration, account linking and rollback/recovery risk | 30 |
| Token verification, expiry, revocation and RLS/Sync integration | 20 |
| Email/password and Google sign-in outcome parity | 15 |
| Offline session/reauthorization behavior | 15 |
| App/MCP/backend complexity and operational burden | 10 |
| Time and evidence needed to retire the temporary path | 10 |

Any security or identity-correlation failure is disqualifying regardless of
score. The score is evidence, not a substitute for product approval of user-
facing migration/recovery behavior.

### Complex optimistic projection (A-015)

Implement three disposable candidates behind one port and the same command ID:

1. pending-operation overlay over last authoritative local rows;
2. tagged optimistic fact rows that cannot be mistaken for server authority;
3. hybrid: authoritative simple facts plus overlay for inseparable multi-record
   effects.

Compare local atomicity, query complexity, restart survival, cross-screen
consistency, server replacement, rejection rollback, unrelated queue progress,
debuggability, and migration/version behavior. A candidate fails if any screen
can render a partial paired operation as authoritative or if one permanent
rejection blocks later independent operations.

### Hosted versus self-hosted PowerSync

The functional spike runs against the intended launch topology. Record the
run-date hosted pricing/limits, projected baseline and 10× monthly cost, synced
bytes, hosted data, operations and operational support. If that exceeds the
product owner's approved run-rate, compare self-hosting with the same functional
and failure suite plus on-call, upgrade, backup, monitoring and security labor.
No fixed price in this document is authoritative.

## Execution Phases

### S0 — Isolation and reproducibility

1. Generate the run ID and manifest before provisioning or app launch.
2. Resolve every endpoint/project/bucket/issuer and compare it with the committed
   production-deny list.
3. Prove staging credentials cannot reach production with non-mutating denied-
   access probes approved for the environment.
4. Seed `tiny`; destroy and recreate the target; reproduce identical checksums.

Exit: isolation tests pass, reset is deterministic, secrets are absent from
artifacts, and cleanup is proven.

### S1 — Postgres authority and RLS

1. Apply disposable spike migrations to an empty target twice (fresh and
   upgrade path).
2. Exercise exact cents, stable IDs, same-Account FKs, unique operation keys,
   immutable result rows, paired command atomicity and deterministic lock order.
3. Run allowed/denied RLS matrices for owner, administrator, ordinary member,
   restricted-financial member, removed member, other Account and service role.
4. Capture `EXPLAIN (ANALYZE, BUFFERS)` for every spike query/policy shape at
   baseline/headroom.
5. Backup, corrupt the disposable target deliberately, restore, and reconcile
   every expected count/hash/invariant.

Exit: zero cross-tenant rows, zero duplicate financial/paired effects, no
unexplained reconciliation difference, no unreviewed sequential scan on bounded
hot paths, and restore RPO/RTO recorded.

### S2 — Auth strategy

Run the complete A-007 matrix for both candidates with synthetic users:

- email/password and Google sign-in, relaunch, refresh and sign-out;
- provider-subject→Principal correlation, account selection and role change;
- expired, malformed, wrong-audience, wrong-issuer and replayed token negatives;
- app, PowerSync and target API agreement on the same Principal;
- recovery/account-link collision and rollback rehearsal; and
- no Firestore/production Storage capability in the temporary candidate.

Exit: disqualifying failures are zero; scores, complexity, migration steps and
retirement plan are reviewable. No provider is selected silently.

### S3 — Encrypted local lifecycle and authorization lease

On each required physical target:

- create/open encrypted per-environment/per-Principal database and Keychain key;
- verify plaintext Account/client/financial markers are absent from raw database
  and common temp/log artifacts;
- terminate during local transaction, upload, download, key rotation, logout and
  cleanup, then relaunch and recover deterministically;
- exercise device lock/unlock, biometric/passcode unavailability, account switch
  and local storage pressure;
- run accelerated token/lease boundary cases plus one real seven-day offline
  soak with cached work and queued operations; and
- verify routine logout blocks on pending operations/media, sync-then-logout
  waits for terminal outcomes, explicit discard names exact counts, and cleanup
  removes database/key/bytes without claiming upload.

Exit: zero silent pending-work loss, zero cross-account database reuse, fail-
closed cleanup, measured lease behavior, and evidence sufficient for the later
A-016 product/security decision.

### S4 — Sync authorization and readiness

For identity bootstrap, Account catalog, Inventory, Project workspace and
bounded historical-detail streams:

- prove exact authorized row sets for every role/account fixture;
- prove current Inventory history is locally explainable through repeated
  acquisition/sale/return/resale without an unseen remote lookup;
- distinguish not-requested, downloading, complete, stale, unauthorized and
  error readiness instead of rendering partial-as-empty;
- revoke membership/financial access while a device is offline, then reconnect;
- inspect the database after stream removal for prohibited retained rows; and
- verify RLS write authorization and Sync download authorization independently.

Exit: zero unauthorized local rows/count leakage, required history evidence is
complete when readiness says complete, and reconnect removes access before any
stale queued operation gains authority.

### S5 — Durable operations and optimistic projection

Run all three A-015 candidates through:

- offline accept→process kill→restart→reconnect→one authoritative result;
- duplicate delivery before/after result, timeout after server commit, and
  reconnect storms;
- stale revision, membership revocation, domain validation failure and command-
  version rejection;
- concurrent operations on the same Items in reversed client order;
- one permanently rejected operation followed by unrelated valid operations;
- server correction/replacement of every optimistic effect; and
- all relevant screens observing one coherent pending/accepted/rejected truth.

Exit: zero duplicate authoritative effects, zero stuck unrelated queue entries,
zero partial paired authority, and one candidate has a documented complexity/
performance advantage without weakening semantics.

### S6 — Attachment durability

- capture bytes offline before metadata claims durable acceptance;
- terminate at every enqueue/hash/upload/finalize/metadata checkpoint;
- resume chunked upload, retry duplicate operation, reject invalid content and
  recover expired credentials;
- verify attachment metadata syncs without bytes and private resolution checks
  authorization at download time; and
- exercise logout pending-work choices and post-upload local eviction.

Exit: zero accepted attachment with missing recoverable bytes, zero public or
bearer-token leakage, one canonical object per idempotent upload, and measured
retry bytes/time.

### S7 — Schema and client-version evolution

Test old-app/new-server, new-app/old-compatible-server, mixed device versions,
additive columns/tables, Sync definition change, local database rebuild and
minimum-supported-contract rejection. Keep destructive removal out of the
compatibility window.

Exit: old client never corrupts new authority, incompatible writes receive a
durable actionable result, local rebuild preserves or explicitly disposes
pending work, and rollback evidence remains usable.

### S8 — Performance, capacity, and cost

Measure tiny/baseline/headroom on each supported target and network profile:

- encrypted database open, workspace readiness and cold initial sync;
- Project/Inventory list, 700-Item workspace, universal search, Item history,
  budget/report snapshot and watched-query update;
- local optimistic visibility, server command p50/p95/p99, authoritative result,
  replication lag and rejection recovery;
- database size, peak memory/CPU, battery/thermal observations, downloaded/
  uploaded bytes and hosted PowerSync data; and
- attachment upload/resume separately by file class.

Proposed hard caps must be approved **before** measurement and recorded in the
manifest. Initial candidates are: cached local list/detail p95 ≤150 ms,
history/report p95 ≤300 ms, optimistic visibility p95 ≤250 ms, no main-thread
stall >250 ms attributable to the data plane, and zero crashes at headroom.
Cold-sync, server-command, replication and monthly-cost caps are set from the
first instrumented baseline plus user expectations before the final run; they
may not be relaxed after seeing a failure without a new versioned run.

Exit: approved caps pass, query plans and indexes are reviewed, storage/network
growth is explainable, and hosted/self-hosted cost at baseline and 10× is
explicitly accepted or rejected.

### S9 — Failure repetition and decision review

Run every correctness/security/fault test at least three times from clean reset,
then rerun the full suite with randomized operation/network ordering. Record
flake signatures as failures until explained and fixed.

Produce one recommendation per architecture gate with:

- exact passing/failing test IDs and raw artifact links;
- chosen/rejected option and tradeoffs;
- measured thresholds, capacity and cost;
- residual risks, owner and required mitigation;
- provider/version constraints; and
- explicit statement that product decisions and production authorization remain
  unchanged.

## Mandatory Test Register

| Test ID | Assertion | Hard failure condition |
|---|---|---|
| `SPIKE-ISO-001` | All configured resources are staging allowlisted | Any production/unknown resource resolves or any staging credential can mutate production |
| `SPIKE-DB-001` | One command is atomic/idempotent under retry/concurrency | Duplicate/partial authority or unexplained cents |
| `SPIKE-RLS-001` | RLS enforces Account/role/financial matrix | Unauthorized row, count, error detail or operation result leaks |
| `SPIKE-AUTH-001` | Provider token maps to one stable Principal | Ambiguous/cross-Account identity or invalid token accepted |
| `SPIKE-ENC-001` | Local database/key lifecycle is protected | Plaintext sensitive marker, key reuse across Principal/environment, or cleanup bypass |
| `SPIKE-OFF-001` | Accepted offline command survives restart/soak | Silent loss or premature authoritative rendering |
| `SPIKE-QUE-001` | Permanent rejection does not poison queue | Later independent accepted command cannot complete |
| `SPIKE-SYNC-001` | Authorized streams are complete and bounded | Unauthorized local row or readiness claims completeness while required evidence is missing |
| `SPIKE-REV-001` | Revocation takes effect safely on reconnect | Stale operation commits after revoked authority or protected rows remain available beyond approved policy |
| `SPIKE-HIS-001` | Repeated Item cycle is explainable offline | Missing acquisition/placement/occurrence/amount/source evidence while marked ready |
| `SPIKE-MED-001` | Accepted offline bytes survive interruption | Metadata claims durable acceptance with unrecoverable bytes or object becomes public |
| `SPIKE-EVO-001` | Mixed schema/client versions fail safely | Corruption, silent drop, unrecoverable queue, or unsupported writer accepted |
| `SPIKE-RST-001` | Backup/restore returns exact authority | Nonzero unexplained reconciliation difference |
| `SPIKE-PERF-001` | Approved performance/capacity caps pass | Any mandatory p95/p99/capacity cap fails |
| `SPIKE-COST-001` | Baseline and 10× run-rate is accepted | Cost/operational burden has no explicit owner approval |
| `SPIKE-PHY-001` | Required physical-device matrix passes | Evidence exists only on simulator or required fault/soak case fails |

## Physical Target Matrix

At minimum run on:

- one currently supported iPhone representative of the oldest supported memory/
  storage class;
- one current supported iPhone/iOS combination;
- one supported Apple-silicon macOS target; and
- Simulator only as an additional deterministic/fault-injection runner.

Record hardware model, OS/build, free storage, battery state, thermal state,
network profile and app build. If the product's supported-device policy differs,
the run manifest must update the matrix before execution, not omit it silently.

## Evidence Layout

Each run writes a gitignored directory outside source artifacts:

```text
artifacts/vertical-spike/<run-id>/
  run-manifest.json
  environment-proof.json
  dependency-lock.json
  fixture-manifest.json
  test-results.json
  junit.xml
  metrics.json
  query-plans/
  reconciliation/
  fault-timeline/
  redacted-logs/
  screenshots/
  cost-model.json
  cleanup-proof.json
  decision-recommendations.md
```

`run-manifest.json` records repository commit/dirty state, protocol version,
resource identifiers, versions, device matrix, test selection, approved caps,
fixture checksums, start/end time, operator and artifact checksums. It never
contains credentials, JWTs, private keys, signed URLs, client content, full
notes, or raw media.

The committed evidence record links the immutable artifact location and records
only safe summaries, hashes, counts, failures and approvals. Prose cannot replace
missing machine-readable results.

## Go/No-Go Rule

The spike passes only when:

- all mandatory tests pass on the required matrix and repeat count;
- security, durability, idempotency, isolation, restore and reconciliation have
  zero tolerated failures;
- performance/capacity/cost remain within thresholds approved before the final
  run;
- A-007 and A-015 recommendations identify one supported option and rejected
  alternatives with evidence;
- A-016 enforcement evidence is complete and awaits/has explicit product-
  security approval rather than being inferred; and
- cleanup proof shows all disposable hosted resources are removed or transferred
  to an explicitly owned ongoing staging budget.

Any mandatory failure yields `no-go`. Partial success may guide fixes but cannot
approve A-003/A-004 or advance a residual surface to `target_mapped`/`verified`.

## Resumption and Tracking

The implementation tracker owns phase status. After each run:

1. validate the run manifest and artifact checksums;
2. add one evidence record with exact test IDs/results;
3. update the architecture decision register only for gates whose evidence and
   required approvals are complete;
4. regenerate the residual queue and remap only surfaces whose final blocker
   actually closed;
5. run all conversion checks/gates; and
6. update `conversion/execution-state.md` with the last completed phase, run ID,
   failures and next exact command.

This makes the spike resumable after context compaction without relying on chat
history or an agent's memory.

## Current Primary References

Revalidate these official sources and pin their observed version/date in each
run manifest:

- [PowerSync Swift SDK](https://docs.powersync.com/client-sdks/reference/swift)
- [PowerSync data encryption](https://docs.powersync.com/client-sdks/advanced/data-encryption)
- [PowerSync write validation errors](https://docs.powersync.com/handling-writes/handling-write-validation-errors)
- [PowerSync RLS and Sync Streams](https://docs.powersync.com/integrations/supabase/rls-and-sync-streams)
- [Supabase Firebase third-party Auth](https://supabase.com/docs/guides/auth/third-party/firebase-auth)
- [Supabase Firebase Auth migration](https://supabase.com/docs/guides/platform/migrating-to-supabase/firebase-auth)
- [Supabase Auth architecture](https://supabase.com/docs/guides/auth/architecture)
