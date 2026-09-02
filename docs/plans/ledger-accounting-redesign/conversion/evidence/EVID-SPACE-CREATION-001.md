# EVID-SPACE-CREATION-001 — Space Creation Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation / provider-free direct Space creation
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-F61D38406022`, `TEST-F46861BCC21A`
- Slice dossier:
  `conversion/implementation-slices/space-creation-operation-contracts.json`
- Verification state: implemented locally; exact implementation-commit CI is
  still required before either claimed surface can become verified
- Ready scaffold hashes:
  - `SpaceCreationOperation.swift`:
    `3a9649300ded0cfa08608c5cec10a0bbfd5e314792e651c2c18e87427dbe9d34`
  - `SpaceCreationOperationTests.swift`:
    `99a735a4001179d517c128d444ca16550604d8ca0410c9ca32f53df0f6d92d57`

## Selection and Scope

After verifying Project details, the next dependency audit rejected Project-
category configuration because its verified read dossier explicitly gates the
writer on O-026. Direct Space creation is the next smallest complete decision-
independent operation. The canonical Space spec, architecture and reviewed
capability dossier agree that a direct create owns stable identity, exact
Project-or-Business-Inventory scope, required name and optional notes while
every other Space concern is a separate typed operation.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The future command cannot create/revise checklists, apply/save a
template, attach media, assign Items, add review evidence, set completion,
archive/delete a Space or mutate accounting. Firebase source paths, application
code, providers, schema and hosted resources remain unchanged.

## Authority Clarification

`docs/specs/spaces.md` was already canonical target authority and already
specified stable Space/scope fields, trimmed current create input, duplicate-
name validity, separate typed assignment, archive-first lifecycle, attachments,
checklists/templates and no accounting effect. The ready checkpoint consolidates
those existing rules in a Target Redesign Requirements section and makes direct
creation's exact boundary explicit: outer-whitespace-normalized nonblank name,
optional normalized notes, immutable Project-or-Inventory creation scope and no
unrelated side effect.

This is a preserve/correct clarification of reviewed behavior, not a new
feature, backend choice, deployment or production behavior.

## Why Open Decisions Do Not Block This Slice

- O-023 governs attachment detach/retention. Direct create carries no media.
- O-026 governs shared category/template/vendor administration. Direct create
  neither applies nor saves a template and carries no shared reference write.
- O-037 governs assigned Items when an existing Space is archived. Direct
  create carries no Item identity, assignment or lifecycle input.
- O-024/O-025 govern Project/Client lifecycle and relationship correction.
  Project scope is a stable reference only; this command changes neither.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  boundary performs no authorization or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable/optimistic implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight product/conversion/architecture requirements and
requires:

- one stable Space ID, exact Account, actor, operation contract, Operation ID
  and finite client time;
- exactly one canonical Project-ID or Business-Inventory creation scope;
- a required outer-trimmed nonblank name and optional outer-trimmed notes where
  nil/whitespace-only is absent, interior text is preserved and no unapproved
  maximum is invented;
- a typed `CreateSpace` intent with no checklist/template/attachment/Item/
  review/lifecycle/completion/accounting/generic-write field;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics with zero expected-revision preconditions for a new stable ID;
- canonical decode-through-validation and atomic changed-scope/payload/
  precondition/subject/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/Project/create authorization and authoritative apply.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Dependency Evidence

The preceding Project-details verification-document checkpoint is immutable:
exact commit `27b2123474957a448097078c7facbf6ed3d8c418` passed Actions run
`33643300146`, with conversion traceability in 11 seconds and the isolated target
environment in 3 minutes 4 seconds.

The source/caller/authority mapping is reviewed in
`EVID-CAPABILITY-SPACES-REVIEW-001` and `EVID-M2-SPACES-REVIEW-001`. The verified
stable domain IDs, shared operation lifecycle and attachment-capture boundary
supply dependencies without authorizing this new command by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces/
review batch and are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The synchronized ledger records 777 surfaces / 762 discovered, 351 mapped-or-
later target-relevant surfaces, 164 residual surfaces and 43 validated blockers.
Thirty-six slices claim 93 target surfaces and 76 are implementation-advanced.
M0 passes. M1/M2 retain exactly their expected 2/164 prerequisite blockers,
with zero structural errors and the same three explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers;
- all 152 existing target tests in 35 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

Exact comment-only ready commit
`fd81c8aed1a88a3cbd8be742a784dd3d1ab72e93` passed immutable GitHub Actions
run `33645504076`: conversion traceability passed in 20 seconds and the isolated
target environment passed in 2 minutes 32 seconds with all 152 then-existing
tests, graph/generated-contract checks, both staging builds and clean tracked
artifacts. That gate authorized only the frozen provider-free implementation.

## Implemented Contract

- `SpaceCreationScope` is exactly either `project(ProjectID)` or
  `businessInventory` and uses a canonical encoding that rejects a missing
  Project ID, a Project ID on inventory, or an unknown scope.
- `SpaceDisplayName` trims outer whitespace, requires a nonblank result,
  preserves interior text, imposes no unapproved maximum, and rejects
  noncanonical serialized values. `SpaceCreationNotes` applies the same outer
  normalization while mapping nil/whitespace-only to explicit absence.
- `SpaceCreationDraft` binds exact Account, actor, operation contract, stable
  Space, immutable scope, canonical name/notes and finite capture time.
  `CreateSpacePayload` contains only Space ID, scope, name and notes.
- `CreateSpaceCommand` derives one Space subject and zero expected-revision
  preconditions through the shared envelope, fingerprint, receipt and replay
  lifecycle and revalidates all duplicated evidence on decode.
- `SpaceCreating` is one narrow provider-free operation port.
  `SpaceCreationFailure` supplies stable bounded codes for invalid values,
  scope/encoding, binding/precondition/subject/fingerprint/receipt mismatch and
  local acceptance failure.

The deterministic adapter uses only the shared `OperationJournal`. It does not
persist a Space row, prove physical local durability, authorize a Project or
Account, or apply anything to a server.

Implementation hashes:

- `SpaceCreationOperation.swift`:
  `1512b0809cd1b32c65c9db28fd72d7fa3a95bb65fe233f69d1469ecae43e374c`
- `SpaceCreationOperationTests.swift`:
  `72de7d9a3db2c8ae5b507e37b44c8348f786e0ad28471c0faecd98d7c49b450d`

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact Project and Business
Inventory scope, normalized name/notes and duplicate-name identity; canonical
byte-identical restart; atomic blank/noncanonical/malformed/rebound/tampered
evidence refusal with stable diagnostics; shared replay/Operation-ID mismatch
semantics; and no false receipt from a failing port.

The complete local implementation gate also passes: all 156 target tests in 36
suites, target environment isolation, generated app/MCP contracts, macOS and
generic iOS Simulator staging builds, conversion/capability/query/residual
controls, M0 and clean diff formatting. The ledger remains at 777 recorded / 762
discovered and 351 mapped-or-later / 164 residual / 43 blockers; 78 target
surfaces are implementation-advanced. M1/M2 retain the expected 2/164 blockers.

`SPACECREATE-TEST-001` through `-004` therefore pass. `-005` remains planned
until immutable exact-implementation-commit CI passes.

## Permanent Limits

This implementation cannot:

- visibly or authoritatively create any Space;
- create or modify a local/server Space row, scope, revision or audit field;
- validate Account membership, Project existence/scope or create rights;
- create/revise checklists, apply/save templates, attach/detach media, assign
  Items, create review notes, set completion or archive/delete a Space;
- create/change Transaction, occurrence, Invoice, budget, payer, placement,
  price or any other accounting state;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app creation flow, MCP tool, transport or catalog entry;
- transform or reconcile a source Space; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
