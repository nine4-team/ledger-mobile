# EVID-PROJECT-DETAILS-UPDATE-001 — Project Details Update Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free Project description update
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-1A34CF88E95E`, `TEST-22878D176671`
- Slice dossier:
  `conversion/implementation-slices/project-details-update-operation-contracts.json`
- Verification state: verified; all five obligations pass at exact
  implementation commit `a532ac9dee5bedca6ade576657fc4fd971841854`
- Ready scaffold hashes:
  - `ProjectDetailsUpdateOperation.swift`:
    `f80752de441941d33245a4d7c260fc6b9100a05a3099a015db1a65c9faf00532`
  - `ProjectDetailsUpdateOperationTests.swift`:
    `dd825723b6c0d3bf4de3d6cb60942ca0e74c6cdcf8fef7ba69bcbfebee04c61e`

## Selection and Scope

After verifying Client archive, the next Phase 1 dependency audit selected
Project details update as the smallest complete decision-independent operation.
The current app already preserves an optional Project description and trims
form input, while the reviewed target taxonomy separates `UpdateProjectDetails`
from Project/Client rename, Client correction, category configuration, media
and lifecycle. The target command therefore owns only a complete normalized
description replacement or clear.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The future command cannot rename/archive/delete/reassign a
Project, change its Client/categories/media/children/accounting/history or
recreate a generic update dictionary. Firebase source paths, application code,
providers, schema and hosted resources remain unchanged.

## Authority Correction

The dependency audit found that `docs/specs/projects.md` already separates an
explicit Target Redesign Requirements section from Firebase mechanics retained
as current/migration evidence, but the product-authority registry still labeled
the whole document `current_product`. The ready checkpoint registers it as the
seventh canonical target spec for the Project/Client/reference batch and makes
the already-reviewed description preserve/correct rule explicit: description
is optional; outer whitespace is not stored; whitespace-only means clear; and
details update cannot mutate the other named Project concerns.

This corrects authority metadata and formalizes feature preservation already
recorded in the capability dossier. It does not add a new product surface,
backend choice, deployment or production behavior.

## Why Open Decisions Do Not Block This Slice

- O-023 governs attachment reference removal/retention. This command carries no
  media field or reference.
- O-024 governs physical Project deletion. This command carries no delete,
  archive, restore or lifecycle input.
- O-025 governs Project Client reassignment and Client merge. This command
  carries no Client identity, copied Client text or relationship input.
- O-026 governs shared reference-data writers and is unrelated to description.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  boundary performs no authorization or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable/optimistic implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight exact product/conversion/architecture requirements
and requires:

- one stable Project ID, exact Account, actor, operation contract, Operation ID
  and finite client time;
- one complete canonical description replacement: trim outer whitespace,
  normalize nil/whitespace-only to clear, preserve accepted interior text and
  invent no unapproved length cap;
- one typed expected Project revision deriving exactly one same-subject
  `expectedRevision` precondition;
- a typed `UpdateProjectDetails` intent with no name/Client/category/media/
  lifecycle/child/accounting/history/generic-write field;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics;
- canonical decode-through-validation and atomic changed-scope/payload/
  precondition/subject/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/Project/revision authorization and authoritative apply.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Dependency Evidence

The preceding Client-archive verification-document checkpoint is immutable:
exact commit `1926a16e87e353853d3e439d62fbc88495ee1c0d` passed Actions run
`33639869188`, with conversion traceability in 8 seconds and the isolated target
environment in 2 minutes 35 seconds.

The source/caller/authority mapping is reviewed in
`EVID-CAPABILITY-PROJECT-REFERENCE-001` and
`EVID-M2-PROJECT-REFERENCE-001`. The verified Project setup and rename contracts
supply the existing Project description/name identity separation and shared
expected-revision/operation dependencies without authorizing this new command
by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The synchronized ledger records 775 surfaces / 760 discovered, 349 mapped-or-
later target-relevant surfaces, 164 residual surfaces and 43 validated blockers.
Thirty-five slices claim 91 target surfaces and 74 are implementation-advanced.
M0 passes. M1/M2 retain exactly their expected 2/164 prerequisite blockers,
with zero structural errors and the same three explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers;
- all 148 existing target tests in 34 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

Exact comment-only ready commit
`119e04559fbf756e2481287963d0367d80d39846` passed immutable GitHub Actions
run `33641244740`: conversion traceability passed in 8 seconds and the isolated
target environment passed in 2 minutes 25 seconds with all 148 then-existing
tests, graph/generated-contract checks, both staging builds and clean tracked
artifacts. That gate authorized only the frozen provider-free implementation.

## Implemented Contract

- `ProjectDescriptionReplacement` canonicalizes optional raw input by trimming
  leading/trailing whitespace, maps nil/whitespace-only to explicit clear,
  preserves accepted interior text and rejects noncanonical serialized values.
- `ProjectDetailsUpdateDraft` binds one exact Account, actor, operation
  contract, stable Project, canonical replacement, reused
  `ExpectedProjectRevision` and finite capture time.
- `UpdateProjectDetailsPayload` contains only Project ID and the canonical
  replacement. `UpdateProjectDetailsCommand` derives exactly one Project
  subject and same-subject revision precondition through the shared envelope,
  fingerprint, receipt and replay lifecycle and revalidates duplicated evidence
  on decode.
- `ProjectDetailsUpdating` is one narrow provider-free operation port.
  `ProjectDetailsUpdateFailure` supplies stable bounded codes for invalid time,
  noncanonical/malformed evidence, binding/precondition/subject/fingerprint/
  receipt mismatch and local acceptance failure.

The command contains no Project name, Client/category/media/lifecycle/child/
accounting/history mutation, generic field map or authoritative update result.
Its deterministic test adapter uses the shared `OperationJournal`; it is not a
physical local or server implementation.

Implementation hashes:

- `ProjectDetailsUpdateOperation.swift`:
  `adb07ec93fef9eae58574c474c20af7841ffbd99ff5a6ca505bc59105d7f7f58`
- `ProjectDetailsUpdateOperationTests.swift`:
  `45087dbf3dd13b10ef8b547a1499e4bfaa640ee54c6457286c47a03f96f1d35b`

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact normalized set/clear
scope and same-Project revision intent, canonical byte-identical restart,
atomic noncanonical/malformed/rebound/tampered evidence refusal with stable
diagnostics, shared exact replay/Operation-ID mismatch semantics and no false
receipt from a failing port.

The complete local implementation gate also passes: all 152 target tests in 35
suites, target environment isolation, generated app/MCP contracts, macOS and
generic iOS Simulator staging builds, conversion/capability/query/residual
controls, M0 and clean diff formatting. The ledger remains at 775 recorded / 760
discovered, 349 mapped-or-later / 164 residual / 43 blockers; 76 target surfaces
are implementation-advanced. M1/M2 retain the expected 2/164 blockers.

`PROJECTDETAILS-TEST-001` through `-004` therefore pass.

## Immutable Exact-Commit Verification

GitHub Actions run `33642777864` verified exact implementation commit
`a532ac9dee5bedca6ade576657fc4fd971841854`:

- conversion traceability passed in 10 seconds;
- the isolated target environment passed in 2 minutes 51 seconds;
- all 152 target tests in 35 suites passed;
- target dependency/provider/source-project isolation and generated app/MCP
  contracts passed;
- macOS and generic iOS Simulator staging builds passed; and
- tracked-artifact cleanliness passed.

`PROJECTDETAILS-TEST-005` therefore passes. All five obligations and exactly the
two claimed target-only surfaces are verified. Hosted evidence adds no server,
physical persistence, authorization, provider, migration or production claim.

## Permanent Limits

This implementation cannot:

- visibly or authoritatively update any Project description;
- create or modify a local/server Project row, revision or audit field;
- rename/archive/restore/delete/reassign a Project or change Client, category,
  media, child, accounting or history state;
- authorize Account membership, Project existence/revision or update rights;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app edit flow, MCP tool, transport or catalog entry;
- transform or reconcile a source Project description; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
