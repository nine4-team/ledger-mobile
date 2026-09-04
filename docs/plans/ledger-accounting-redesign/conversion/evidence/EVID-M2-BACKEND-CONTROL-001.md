# EVID-M2-BACKEND-CONTROL-001 — Backend, Security, Storage, and Query Target Mapping

- Timestamp: 2026-09-03 correction
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  from the history now carried by `firebase`; the historical audit began from a
  dirty source checkout
- Production reads or mutations: none
- Target implementation/schema/RLS/Storage/Sync Stream changes: none
- Operator: Codex
- Mapping batches: `M0-BACKEND-AUTH-001`, `M0-BACKEND-FUNCTIONS-001`,
  `M0-BACKEND-RULES-001`, `M0-BACKEND-STORAGE-001`,
  `M0-QUERY-PROFILE-001`
- Method: `target-mapping-method.md`

## Scope and Result

The five batches contain 62 `replace`, `redesign`, or `migrate` surfaces.
Thirty now have complete target maps. Thirty-two remain deliberately unresolved
because a named product/architecture decision or the canonical production
profile can still change/discover their exact security, lifecycle, data or
migration mapping. `MAN-DATA-001` remains `blocked`, preserving the M1 evidence
gate; no prose mapping was allowed to bypass it.

## Mapping Decisions

- Firebase Auth/account/member/invite services map to stable Principal,
  membership, Account and invite ports/handlers. Provider IDs are correlation
  evidence; app and MCP share one membership authority. Provider selection and
  offline session lease remain held where they change the adapter/lifecycle.
- Firebase Hosting/custom invite URLs map to stable allowlisted product routes;
  URLs never grant membership. Firebase Admin/MCP initialization maps to one
  validated environment composition with no static actor/Account fallback.
- Account bootstrap/invite Functions map to typed atomic handlers. Category
  seeding is an idempotent bootstrap responsibility. Budget summary triggers map
  to rebuildable stable contribution projections; correctness never depends on
  asynchronous Cloud Functions.
- Reviewed Firestore rules map capability-by-capability to immutable tenant
  ownership, existing/resulting-row RLS, handler authorization and paired Sync
  Stream tests. O-040 withholds the personal-preference rule shape until the pin
  feature and ownership/default/fallback contract is approved; health is separate
  from data readiness; Fee/note policies are bounded and revision-aware.
- Source query/index catalogs map to a `TargetQueryIndexManifest`, PowerSync
  local index plan and measured Postgres query-plan evidence. Generic app/MCP
  repository/path helpers map to named typed local/server queries and are absent
  from the target runtime.
- Globally open Firebase Storage maps to private parent-authorized objects,
  stable AttachmentIDs, protected durable local bytes, signed delivery and
  source object/reference reconciliation. The target runtime resolves no
  Firebase URLs and contains no Firebase Storage adapter.

## Withheld Surfaces

The 32 held entries name only A/O decisions or canonical production-profile
evidence. They include occurrence/Transaction/Invoice/Space/reference-writer
rules and trigger behavior, Auth/offline session choices, proto migration,
object retention, unprofiled dynamic data and the blocked production data
surface. This prevents a source rule/Function from becoming accidental target
business authority.

## Verification

Required per-batch outcomes are: Auth 7 mapped/3 held; Functions 5/10; rules and
manual data/index 10/17; Storage 6/2; query profile 2/0. Every mapped entry has
non-empty owner, target surfaces, security, Sync, migration rule,
reconciliation, tests and acceptance fields.

This evidence proves reviewed target mapping only. It does not choose Auth,
access/profile production, create DDL/RLS/Storage/streams, deploy Functions/MCP,
implement Firebase compatibility, migrate data, release, or cut over.
