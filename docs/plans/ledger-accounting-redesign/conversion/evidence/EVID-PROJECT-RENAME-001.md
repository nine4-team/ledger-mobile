# EVID-PROJECT-RENAME-001 — Project Rename Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation / provider-free Project rename command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-797909434B82`, `TEST-3CE7B387E9B7`
- Slice dossier:
  `conversion/implementation-slices/project-rename-operation-contracts.json`
- Verification state: implemented; four local behavioral obligations pass and
  exact-implementation-commit CI remains planned
- Implementation hashes:
  - `ProjectRenameOperation.swift`:
    `8fff3525aa272d8659d23487a48bea388f0a9c525feb097f877f468fd55dfaf7`
  - `ProjectRenameOperationTests.swift`:
    `c5e2bdbb661ebf867ecae418e9fe51f7c1f2167ae1b01c997bdfdef2429c362a`

## Selection and Scope

After verifying Client rename, the remaining Phase 1 Project/Client/reference
dependency audit selected Project rename as the next smallest complete user
outcome. Stable Project identity, Project setup, archive, Client identity and
directory reads are already verified. The canonical target relationship keeps
one stable ProjectID bound to one ClientID, while the reviewed capability
contract makes Project and Client names mutable display values rather than
relationship or authorization keys.

Project detail/category editing was not folded into rename because it is a
separate conflict-aware operation. Client reassignment, Client merge and
physical deletion remain gated by O-024/O-025. This slice can express only one
expected-revision Project display-name intent without deciding any of them.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. No current app/MCP surface is treated as replaced until concrete
schema, authorization, Sync, UI/MCP and migration behavior is implemented and
verified.

## Why Open Decisions Do Not Block This Slice

- D-006 settles the stable Account-scoped Project-to-Client relationship. The
  payload cannot carry or alter ClientID and equal display names confer nothing.
- O-024/O-025 govern physical Project deletion, Client correction/reassignment
  and merge. The rename payload cannot express lifecycle or relationship change.
- Description, category configuration, media, children, accounting and
  historical displays are excluded from the command rather than guessed.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  command carries actor/Account binding but performs no authorization or
  physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements and
requires:

- one stable ProjectID inside one immutable Account plus one validated nonblank
  replacement `ProjectDisplayName`;
- exact separation from Client relationship/name, Project description,
  category/media/child/accounting/history and every lifecycle operation;
- one typed expected Project revision on the exact Project subject;
- the shared Account/actor/contract/Operation/time/fingerprint/receipt lifecycle
  with canonical decode-through-validation and byte-identical restart;
- atomic refusal for invalid text/time and rebound Account/actor/contract/
  Project/name/revision/payload/subject/precondition/fingerprint/receipt
  evidence; and
- one narrow provider-free rename port with exact replay and no false receipt.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, authoritative Project/downstream projection, app/MCP, migration,
observability and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, reference-port and exact-commit operational obligations.

The ready checkpoint passed from the dedicated Supabase worktree:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- the existing complete target package suite (116 tests in 26 suites), while
  the two scaffolds add no executable Project rename test;
- target environment and generated-contract checks;
- macOS and generic iOS Simulator staging builds; and
- `git diff --check`.

The synchronized ledger records 759 surfaces, including 744 discovered and 15
manual surfaces. It reports 333 mapped target-relevant surfaces, 164 residual
surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly their
expected 2 and 164 blockers. Conversion, capability, query, residual, target-
environment and generated-contract controls pass. The complete package suite,
macOS staging build and generic iOS Simulator staging build pass without adding
executable behavior to either comment-only scaffold.

Passing this ready gate authorizes only the bounded provider-free implementation
named in the dossier.

Exact ready commit `18ab228379e9d81db1dc35c16bf6eecc867b64cc`
passed immutable GitHub Actions run `33614187250`: conversion traceability
passed in 9 seconds and the isolated target job passed in 3 minutes 1 second
with all 116 then-existing tests, graph/generated-contract checks, macOS and
generic iOS Simulator builds and clean tracked artifacts.

## Implemented Contract

- `ProjectRenameDraft` binds one Account, actor, contract version, OperationID,
  stable ProjectID, validated replacement `ProjectDisplayName`, the existing
  typed `ExpectedProjectRevision`, and finite capture time.
- `RenameProjectPayload` contains only ProjectID and the new display name.
  `RenameProjectCommand` uses the shared `OperationEnvelope`, derives the exact
  Project subject and fingerprint, requires exactly one same-subject expected-
  revision precondition, and decodes only through the same validation path.
- The command has no Client, prior-name, description, category, media,
  lifecycle, child, accounting, history or correction input. Equal Project or
  Client names therefore cannot change identity, relationship or authority.
- `ProjectRenaming` is the narrow provider-free operation port. Exact receipt
  validation is limited to the shared OperationID lifecycle and makes no
  authoritative Project-row or downstream-projection claim.

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact Project/name/revision
command shape, canonical byte-identical restart, stable refusal of malformed or
rebound Account/actor/contract/Project/name/revision/subject/precondition/
fingerprint/receipt evidence, shared `OperationJournal` replay and changed-
intent mismatch behavior, and no false receipt from a failing port.

The complete local gate also passes: all 120 target tests in 27 suites, target
environment isolation, generated app/MCP contracts, macOS staging build,
generic iOS Simulator staging build, conversion/capability/query/residual
controls, M0 and clean diff formatting. The synchronized ledger remains at 759
recorded / 744 discovered surfaces, 333 mapped / 164 residual / 43 blockers.
M1 and M2 retain exactly their expected 2 and 164 blockers.

The exact-implementation-commit operational obligation remains planned until
immutable hosted CI passes for the committed checkpoint.

## Permanent Limits

This ready plan cannot:

- rename a visible/local or authoritative Project row or downstream projection;
- change/infer Client identity, edit description/category/media/child/accounting
  evidence, or use equal names as relationship or authorization proof;
- archive/restore/delete a Project, merge/reassign a Client or decide O-024/
  O-025;
- authorize the actor, resolve membership/capability or enforce a server revision;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app form, MCP tool/resource, transport or catalog entry;
- transform, backfill or reconcile a source Firebase Project/name; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
