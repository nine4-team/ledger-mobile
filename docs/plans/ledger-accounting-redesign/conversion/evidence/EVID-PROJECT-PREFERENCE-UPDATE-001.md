# EVID-PROJECT-PREFERENCE-UPDATE-001 — Project Preference Update Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free current-Principal Project
  preference update command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-8668DE2251DE`, `TEST-AC9956AE9D5C`
- Slice dossier:
  `conversion/implementation-slices/project-preference-update-operation-contracts.json`
- Verification state: ready; executable implementation and all five obligations
  remain planned
- Ready scaffold hashes:
  - `ProjectPreferenceUpdateOperation.swift`:
    `c4a7b0e2ded21ec3e58d31879f6e0a928c3caeb154ea9e5b6013f81e2e3bf2d5`
  - `ProjectPreferenceUpdateOperationTests.swift`:
    `4be5b489939234919cc3c5ad3e5f1f1d949ef36a6ebbfb8f4f8ba0a05d1f3f2a`

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
expected 2 and 164 blockers. Exact ready commit/Actions evidence remains to be
recorded. Passing that external gate will authorize only the bounded provider-
free implementation named in the dossier.

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
