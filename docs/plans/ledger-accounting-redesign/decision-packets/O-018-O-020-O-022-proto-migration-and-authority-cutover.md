# Decision Packet — O-018/O-019/O-020/O-022 Proto Migration and Authority Cutover

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Legacy Capture Migration, Item Reconciliation, Compatibility, Cutover
Unlocks: 5 unique residual surfaces (O-018: 3; O-019: 3; O-020: 2; O-022: 2)
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject this migration/cutover policy:

> Import every legacy proto capture as immutable source evidence and resolve it
> deterministically to one real target Item, an explicit merge into an existing
> Item, or a migration-review record. The target has no ProtoItem writer/reader.
> Matching is suggestion-only until an authorized reviewer selects the physical
> identity; financial/placement/media evidence merges through typed rules and
> source correlation, never by deleting the losing source first.

> Real Unaccounted For target Items and all redesigned writers remain disabled in
> production until the complete target contracts, migration reconciliation and
> Firebase source cutoff pass. Cutover is one maintenance/freeze/final-export/
> import/reconcile/activate operation. Firebase receives no v2 domain schema,
> adapter or dual writer. The only Firebase changes permitted are the minimum
> reviewed operational gates needed to stop current writes and reject stale
> writers. If pending/late-write recovery cannot be proven without an
> intermediate app release, cutover remains blocked or the user explicitly
> approves a narrower loss/risk policy; this packet does not silently authorize
> that release or data-loss risk.

## Confirmed Constraints

- New target capture creates real Items and no proto record.
- Existing Firebase app/proto behavior remains unchanged before hard cutover.
- Rehearsal repeatedly imports immutable Firebase snapshots into isolated
  Supabase/PowerSync staging; it never writes production source.
- One physical object has one Item identity. Duplicate/evidence reconciliation
  cannot clone paid history or delete media/relationships.
- Target app/MCP use only Supabase/PowerSync authority after activation and do
  not contain a Firebase domain adapter, target dual read or v2 Firestore writer.
- Old offline Firebase clients can reconnect after a final export unless source
  writes are rejected. Server isolation alone does not recover their local-only
  bytes/writes.
- A-003/A-004 remain proposed until the vertical spike passes; documentation is
  not migration or cutover authorization.

## Options

### Option A — Keep proto/real dual-read and incrementally activate target writers

Reject. It preserves two runtime identity/authority models and allows old
Firebase writes to race target migration and accounting.

### Option B — Automatically convert/match everything and ignore late writes

Reject. Heuristic identity merges can erase or duplicate physical/financial
history, and an offline old client can write source data after the final export.

### Option C — Deterministic disposition, reviewed matching, and hard authority
cutoff (recommended)

Give every proto a create/merge/already-represented/review/approved-omission
outcome, make matching suggestion-only, keep target writers disabled through
rehearsal/reconciliation, then freeze source writers and activate the target as
one controlled boundary. If pending/late-write safety is unproven, remain
blocked or obtain a separate explicit risk decision.

## Proto Resolution Outcomes

Every source proto record receives exactly one durable disposition:

| Outcome | Required evidence/effect |
|---|---|
| create real Item | Minimum identifying evidence passes; stable target Item ID and all source fields/media/correlation imported |
| merge evidence into Item | Reviewer selects exact existing physical Item; compatible fields/media/provenance merge under typed rules |
| already represented | Deterministic prior conversion/correlation proves source is already represented; no duplicate write |
| migration review | Missing/ambiguous/conflicting identity, media, placement, payer/acquisition or duplicate evidence is retained with exact reason/action |
| approved omission | Only for proven non-domain/test/corrupt artifact under explicit reviewer policy; raw evidence/hash remains in journal |

There is no silent drop, random Item ID on retry, target ProtoItem, or automatic
financial Link from `assignmentHint`, candidate Transaction, status or text.

## Duplicate/Evidence Reconciliation

Candidate matching may rank by stable prior conversion correlation, exact media
content hash, SKU/vendor/date/amount, normalized name/note and Project/Space
context. Scores explain suggestions but never authorize identity.

`ReconcileDuplicateItemEvidence` requires an authorized reviewer to choose:

- the one surviving physical Item identity;
- which descriptive values win or remain as source aliases;
- attachment reuse/copy/reference outcomes under O-023;
- compatible placement/acquisition/occurrence/Invoice/Transaction relationships;
  and
- exact conflicts that remain quarantined.

Safe merge rules:

- source evidence and correlation are append-only;
- media is referenced/deduplicated by stable Attachment identity/hash and not
  deleted during merge;
- empty/less-complete descriptive fields may be filled, but conflicting values
  remain in audit/review rather than last-write-wins;
- one current placement is selected only from proven chronology/reviewer action;
- financial facts are never summed or moved merely because two Items look alike;
  and
- a losing target Item may be tombstoned/aliased only when no independent paid,
  placement or physical-history evidence would be erased.

If both candidates have incompatible immutable accounting/physical histories,
automatic merge is prohibited. Keep both stable identities in review until an
administrative correction plan can preserve every fact.

## Target Activation Gate (O-020)

Production target authority remains closed until all are true for the activation
scope:

- target Product decisions/schema/handlers/RLS/Sync/query contracts are approved;
- staging vertical spike and physical-device offline tests pass;
- app and MCP target release candidates share contract/authority versions;
- immutable source export/profile covers all required data/media/reference shapes;
- every source row/proto/reference is mapped, reviewed/quarantined or approved
  omission with zero unexplained accounting/provenance difference;
- open proto/reconciliation queues meet the explicitly approved activation
  threshold (recommended: zero unresolved records that could alter identity,
  money, placement or retained media);
- final migration artifact, reset rehearsal, interruption/resume, rollback and
  observability pass; and
- O-022 freeze/pending/late-write procedure is approved and ready.

Before activation, target production may contain imported/shadow data but target
user/MCP writes are disabled by server authority version. The public Firebase app
remains authority. At activation, all redesigned writer families switch together;
no per-feature dual authority.

## Firebase Source Freeze and Late Writers (O-022)

### Operational boundary

The minimum cutoff controls are:

- enter explicit accounting maintenance;
- stop/deny current Firebase app accounting writes at Firestore rules;
- deny current Firebase Storage uploads/deletes affecting migrating evidence;
- disable/reject old Firebase MCP/Admin/callable mutators that bypass rules;
- wait for in-flight trusted writers to quiesce and record a cutoff barrier;
- take verified final backup/export and Storage/reference manifest; and
- keep the source read-only through import/reconciliation/target activation and
  rollback-evidence window.

These controls implement no Client, occurrence, Expense, Transfer, Invoice,
budget or provenance v2 behavior in Firebase. They do not make Firebase conform
to target ports.

### Pending-work proof

Before freeze, the runbook inventories every known writer and requires an
explicit disposition for:

- server-acknowledged writes after the rehearsal snapshot (included in final
  delta);
- current online client queues/in-flight operations;
- known offline devices/users and unuploaded media;
- MCP/Functions/Admin jobs and scheduled/background work; and
- writes rejected after the barrier.

The recommended no-loss gate requires positive evidence that every in-scope
known user/device has synchronized or explicitly exported/dispositioned pending
work before the final barrier, plus a documented quiet period and zero in-flight
server writers. A generic “no recent writes” timestamp is insufficient proof for
an offline-first app.

Current Firebase SDK queues/local-only bytes are not magically present in the
server export. If the existing app cannot expose/flush/export them under the
approved process, the honest outcomes are:

1. keep cutover blocked;
2. explicitly approve a narrower per-account/device maintenance/risk policy; or
3. separately authorize a minimal cutover-safety release whose only scope is
   pending-work inspection/export/recovery—not Firebase v2 or an adapter.

This packet recommends outcome 1 until proof exists. It does not pre-authorize
outcomes 2 or 3.

### Rejected stale writers

After freeze, an old client write must fail explicitly at the backend. The
operator records rejected-write telemetry where possible without accepting the
domain mutation. Recovery instructions identify the affected user/device/source
record and route recoverable user evidence into a reviewed target re-entry/import
flow. The target never reopens Firebase or silently replays untrusted legacy
writes after activation.

## Cutover Sequence

1. Verify signed run manifest, exact commits/artifacts/environments/accounts,
   backups, target disabled state and rollback boundary.
2. Enter user-visible maintenance and complete the approved pending-work gate.
3. Freeze Firestore/Storage and every privileged old writer; record barrier.
4. Take/verify final immutable Firebase/Auth/Storage export and delta hashes.
5. Run exact rehearsed target migration dry run; abort on drift/blocker threshold.
6. Commit idempotent target import with journal and interruption recovery.
7. Reconcile every source mapping, money cent, relationship, attachment and
   quarantine; target writes remain disabled.
8. Activate one Supabase/PowerSync authority/contract version for app and MCP.
9. Run post-activation security/offline/accounting/reconciliation smoke and
   monitor rejected stale Firebase writers.
10. Reopen target writes only if all gates pass; retain Firebase read-only
    evidence. Do not contract/delete source during the rollback window.

Rollback before target writes open may reset target and restore source according
to the rehearsed plan. After target-only writes open, returning to Firebase
requires an explicit reconciled back-migration; toggling a flag is not safe.

## Conceptual Migration/Control Shape

| Family | Responsibility |
|---|---|
| immutable source export manifest | Project/account/time/hash/collection/object coverage and provenance |
| source-to-target journal | Every source record/reference/object disposition and deterministic target IDs |
| migration review records | Raw protected evidence, reason, candidates, reviewer decision and resolution |
| Item aliases/correlation | Losing source/target identities resolving to one physical Item without erasing history |
| migration runs/checkpoints | Artifact version, batch cursor, attempts, interruption/resume and result |
| authority/release manifest | Exact source/target environment, contract version, disabled/active state and operators |
| freeze/rejected-write evidence | Barrier, writer inventory, pending-work dispositions and recovery events |
| reconciliation results | Counts/hashes/cents/relationships/media/readiness differences and approvals |

Migration/control tables are private administrative data, not ordinary app Sync
Streams. RLS/grants deny app/MCP access except explicit safe migration-review
work queues for authorized operators. Credentials are environment-bound and dry-
run by default.

## Required Acceptance Tests

### Proto and duplicate reconciliation

- each name/photo/note/empty/partial proto fixture creates Item, merges, maps
  already represented, reviews or omits exactly once with stable IDs;
- hint/candidate/status alone never creates payer/acquisition/accounting authority;
- exact media hash/source correlation suggests but does not auto-merge;
- safe merge preserves fields/media/relationships/audit; incompatible paid or
  placement histories block without deleting either identity;
- repeated/interrupted import and reviewer retry produce one result; and
- target runtime contains no proto/Firebase repository or writer.

### Activation and cutoff

- target production shadow data rejects app/MCP writes before authority activation;
- Firestore rules, Storage policy, MCP/Admin/callable controls reject every old
  mutator after barrier while allowed evidence reads remain as approved;
- final delta includes every server-accepted pre-barrier write and no post-barrier
  mutation;
- known offline/pending/unuploaded cases cannot be marked resolved without exact
  evidence/disposition;
- inability to prove pending-work recovery keeps cutover blocked;
- import/reconciliation failure never opens target writes;
- app/MCP activate the same contract version and old Firebase mutators stay off;
- stale rejected-write recovery does not silently replay or lose evidence; and
- rollback before activation and freeze-after-target-write behavior match the
  rehearsed runbook.

### Security and reconciliation

- staging/migration credentials cannot target production accidentally; exact
  source/target/account/mode guards fail closed;
- no service key/source token/raw PII appears in logs/manifests/review Sync;
- every source proto/Item/relationship/object maps or has explicit reviewed
  disposition; cents/hashes/cardinality/readiness reconcile; and
- production Firebase is never mutated during profiling/rehearsal and no source
  object is deleted during initial cutover/rollback retention.

## Approval Consequences

If approved:

1. update canonical proto/Item/offline/migration/cutover specs and confirmed
   decisions;
2. promote importer/reconciliation/activation/freeze contracts into architecture
   03/04/05/06/07/08 and production runbooks;
3. remap the five affected surfaces while retaining canonical production
   profile/reference evidence, A-003/A-004/A-007/A-015/A-016 and physical target
   verification blockers;
4. build only isolated migration/staging controls until implementation is
   separately authorized; and
5. do not schedule production cutover until the pending-work proof has an
   accepted testable mechanism.

## Approval Checklist

- [ ] Every proto becomes one Item, reviewed merge, explicit review or approved
  omission; target has no ProtoItem runtime.
- [ ] Duplicate matching is suggestion-only and financial/media history is never
  erased by merge.
- [ ] Target production writers remain disabled until all gates/reconciliation
  pass.
- [ ] Cutover freezes current Firebase writers, then final-exports/imports/
  reconciles/activates; no v2 Firebase backend or adapter exists.
- [ ] No-loss pending/offline evidence must be proven; otherwise cutover blocks or
  requires a separately explicit risk/release decision.
- [ ] Firebase source remains read-only evidence through rollback retention.
