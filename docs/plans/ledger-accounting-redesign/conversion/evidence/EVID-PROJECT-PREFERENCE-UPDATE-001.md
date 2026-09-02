# EVID-PROJECT-PREFERENCE-UPDATE-001 — Project Preference Update Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free current-Principal Project
  preference update command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-8668DE2251DE`, `TEST-AC9956AE9D5C`
- Slice dossier:
  `conversion/implementation-slices/project-preference-update-operation-contracts.json`
- Verification state: implemented; four deterministic obligations pass locally,
  exact-implementation-commit operational evidence remains planned
- Implementation hashes:
  - `ProjectPreferenceUpdateOperation.swift`:
    `fe54fb28fe1e772c222976a2953402f267faa1e6c95fa48a1433e21b6abbc2c8`
  - `ProjectPreferenceUpdateOperationTests.swift`:
    `6af5561e63199d40831281b6c1eb4ffd7ba68f5926916f9269849aed78b93292`

## Selection and Scope

After verifying current-Principal Project preference reads, the next Phase 1
dependency audit selected `UpdateProjectPreferences` as the smallest complete
decision-independent mutation. The canonical specs settle that pins are
per-user, per-Project, ordered presentation state; they do not affect category
definitions or budget accounting. The reviewed capability and architecture
contracts explicitly name a current-Principal preference command and require a
conflict-aware durable operation.

The command will replace the complete ordered pin set. Its expected state must
be either authoritatively not stored or one exact revision, preserving the
difference between an absent row and a stored empty preference. This gives an
offline first write enough intent to detect concurrent edits without inventing
merge or last-write-wins behavior.

O-026 does not block this slice: it governs shared categories, templates and
vendor suggestions. This command cannot create, edit, archive, reorder or grant
authority over any shared reference. Category lifecycle resolution, automatic
first-use Furnishings behavior and deleted-reference cleanup remain separate
later responsibilities rather than hidden command behavior.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. No current app/MCP surface is treated as replaced until concrete
schema, authorization, Sync, UI/MCP and migration behavior is implemented and
verified.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements and
requires:

- one exact Account/actor/Project preference owner with no separate caller-
  supplied target user;
- one complete ordered duplicate-free stable BudgetCategoryID replacement,
  including valid empty state and no category labels, amounts or definitions;
- explicit `notStored` versus exact revision intent mapped to one same-subject
  expected-state or expected-revision precondition;
- the shared Account/actor/contract/Operation/time/fingerprint/receipt lifecycle
  with canonical decode-through-validation and byte-identical restart;
- atomic refusal for duplicate pins, invalid time and rebound Account/actor/
  contract/Project/pins/expected-state/payload/subject/precondition/fingerprint/
  receipt evidence; and
- one narrow provider-free update port with exact replay and no false receipt.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, authoritative preference/category projection, default/cleanup
policy, app/MCP, migration, observability and feature activation are explicit
nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, reference-port and exact-commit operational obligations.

The preceding Project preference read verification-document checkpoint is also
immutable: exact commit `f19492b800961a4db517eb7a91a1249841b5be5f`
passed Actions run `33625052445`, with conversion traceability in 14 seconds and
the isolated target environment in 1 minute 46 seconds.

The complete local ready gate passes:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2 and 164 prerequisite blockers;
- all 132 existing target tests in 30 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds;
- repeatable XcodeGen output with matching
  `253619389c017f896a394259c4b16004aa0863abf5b520791e63417c228b8ab2`
  graph hashes and no source-project diff; and
- clean diff formatting.

The synchronized ledger records 767 surfaces, including 752 discovered and 15
manual surfaces. It reports 341 mapped target-relevant surfaces, 164 residual
surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly their
expected 2 and 164 blockers.

Exact ready commit `30a131e8305b838f32854601db44ae5aeacbfe7b`
passed immutable GitHub Actions run `33626533989`: conversion traceability
passed in 10 seconds and the isolated target job passed in 2 minutes 25 seconds
with all 132 then-existing tests, graph/generated-contract checks, macOS and
generic iOS Simulator builds and clean tracked artifacts. That gate authorized
only the bounded provider-free implementation named in the dossier.

## Implemented Contract

- `ProjectPreferenceExpectedState` distinguishes `notStored` from one exact
  `revision(UInt64)` and produces one matching same-subject operation
  precondition. A stored preference with an empty pin list remains distinct from
  authoritative absence.
- `ProjectPreferenceUpdateDraft` binds one Account, actor Principal, contract
  version, stable Project, complete ordered duplicate-free pin replacement,
  expected state and finite capture time. It carries no separate target user,
  category label/lifecycle/amount or financial result.
- `UpdateProjectPreferencesCommand` derives a bounded SHA-256 reference-data
  subject from exact Account/Principal/Project identity, binds the minimal
  payload and precondition to the shared envelope/fingerprint, and decodes only
  through the same validation path.
- `ProjectPreferenceUpdating` is the narrow provider-free command port. Receipt
  validation is limited to the shared OperationID lifecycle and makes no
  preference-row, category-resolution or authoritative-apply claim.

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact current-Principal scope,
ordered complete replacement, absent/revision preconditions, stored-empty and
reordered canonical restart, duplicate/rebound/tampered refusal, stable bounded
diagnostics, shared `OperationJournal` replay/mismatch semantics and no false
receipt from a failing port.

The complete local implementation gate also passes: all 136 target tests in 31
suites, target environment isolation, generated app/MCP contracts, macOS
staging build, generic iOS Simulator staging build, conversion/capability/query/
residual controls, M0 and clean diff formatting. The synchronized ledger remains
at 767 recorded / 752 discovered surfaces, 341 mapped / 164 residual / 43
blockers. M1 and M2 retain exactly their expected 2 and 164 blockers.

Exact-implementation-commit CI remains planned, so all four deterministic
obligations pass but the operational obligation and the two claimed surfaces
remain `implemented`, not `verified`.

## Permanent Limits

This ready plan cannot:

- persist, display or authoritatively apply a Project preference;
- authorize the caller, target another Principal or resolve membership;
- create/edit/archive/reorder a category or decide O-026;
- synthesize a first-use default, validate category visibility, silently clean
  stale/deleted references or calculate any budget value;
- define a Postgres table, handler, grant, RLS policy, Sync Stream, optimistic
  projection or durable local store;
- wire a current/target app control, MCP tool/resource, transport or catalog;
- transform, backfill or reconcile a Firebase preference; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
