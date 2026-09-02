# EVID-SPACE-CHECKLIST-REVISION-001 — Space Checklist Revision Operation Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free Space checklist revision
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-EB8803C0864A`, `TEST-9A22BFF16437`
- Slice dossier:
  `conversion/implementation-slices/space-checklist-revision-operation-contracts.json`
- Verification state: ready scaffold only; executable behavior remains absent
  until immutable exact-ready-commit CI passes
- Ready scaffold hashes:
  - `SpaceChecklistRevisionOperation.swift`:
    `351c778e83be64ae8b456c3863af293a07aca86ca8a1c770b67a76ebcd40f693`
  - `SpaceChecklistRevisionOperationTests.swift`:
    `7b8c967eb0d77259cc32d19ff596d3fd0fd752ca8446e18665293616a697bbcb`

## Selection and Scope

After verifying Space creation and details editing, the dependency audit
selected `ReviseSpaceChecklists` as the next smallest complete decision-
independent operation. The shipped app preserves add/remove/rename/reorder/
check behavior by rewriting one embedded checklist array. The canonical Space
spec and reviewed target capability already separate checklist revision from
Space details, templates, media, Item assignment, review notes, reconciliation
and archive. The target command therefore owns one complete ordered hierarchy
replacement for one stable Space and expected revision.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The future command cannot change Space scope/name/notes,
apply/save templates, attach media, assign Items, create review evidence, set
Space completion/lifecycle or mutate accounting. Firebase source paths,
application code, providers, schema and hosted resources remain unchanged.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/spaces.md` for stable checklist/item identity, structure,
  checked-state progress, valid empty checklists and operation separation;
- the reviewed Spaces capability dossier for expected revision, deterministic
  order, typed conflicts and explicit correction of random decoded IDs and
  last-write-wins embedded-array updates;
- the shipped `Space` DTO, `EditChecklistModal`,
  `SpaceDetailView.saveChecklists` / `toggleChecklistItem`, list/detail
  calculations and integration/model tests for the user-visible add/remove/
  rename/reorder/check/progress outcomes;
- current MCP Space tooling, which exposes progress reads but no checklist
  mutation and therefore does not establish target app/MCP parity; and
- the architecture's typed command, operation-envelope and narrow Space port
  boundaries.

The target clarification preserves the visible outcomes while making the
implicit quality rules explicit: outer-trimmed nonblank names/text, stable
distinct nested IDs, unique explicit order, complete replacement, exact stale
conflict, empty collection as clear, and zero-item checklist validity.
Duplicate labels remain valid because identity is never text. No unapproved
length cap, merge policy or completion state was invented.

## Why Open Decisions Do Not Block This Slice

- O-023 governs attachment detach/retention. Checklist revision carries no
  media.
- O-026 governs shared reference administration. This operation cannot read,
  apply, save, edit, archive or reorder a Space template.
- O-032 governs Transaction posting/review readiness. Checklist checked state
  is ordinary Space progress, not Transaction posting or legacy
  `Space.isComplete`.
- O-037 governs assigned Items when a Space is archived. This operation carries
  no Item identity, assignment, archive or lifecycle input.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  boundary performs no authorization or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable/optimistic implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight product/conversion/architecture requirements and
requires:

- distinct stable Space, checklist and checklist-item identities;
- one complete deterministically ordered checklist hierarchy, with unique
  identity/order within each owning scope;
- canonical outer-trimmed nonblank checklist names and item text, preserved
  interior text, duplicate labels and no target length cap;
- every item's explicit checked state, derived completed/total progress, valid
  empty clear and valid zero-item checklist;
- one expected Space revision deriving exactly one same-Space
  `expectedRevision` precondition;
- a typed `ReviseSpaceChecklists` intent with no scope/details/template/media/
  Item/review/Space-completion/lifecycle/accounting/generic-write field;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics, canonical decode-through-validation, and atomic changed-hierarchy/
  precondition/subject/fingerprint/receipt refusal; and
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests, permanently separated from later trusted authorization and
  authoritative application.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Dependency Evidence

The preceding Space-details verification-document checkpoint is immutable:
exact commit `01d3638b2b7850f39a7a16e1b899b37ce441e189` passed Actions run
`33655871244`, with conversion traceability in 8 seconds and the isolated
target environment in 2 minutes 36 seconds.

The source/caller/authority mapping is reviewed in
`EVID-CAPABILITY-SPACES-REVIEW-001` and `EVID-M2-SPACES-REVIEW-001`.
Verified Space identity, expected revision and shared operation lifecycle
supply dependencies without authorizing this new command by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces/
review batch and are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The synchronized ledger records 781 surfaces / 766 discovered, 355 mapped-or-
later target-relevant surfaces, 164 residual surfaces and 43 validated blockers.
Thirty-eight slices claim 97 target surfaces and 80 are implementation-advanced.
M0 passes. M1/M2 retain exactly their expected 2/164 prerequisite blockers,
with zero structural errors and the same three explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers;
- all 160 existing target tests in 37 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

## Permanent Limits

This ready checkpoint cannot:

- visibly or authoritatively update any checklist or Space;
- create or modify a local/server Space/checklist row, revision or audit field;
- change Space scope, name, notes, template/media/Item/review/reconciliation/
  lifecycle state or any accounting state;
- validate Account membership, Space existence/revision or update rights;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app checklist flow, MCP tool, transport or catalog
  entry;
- transform or reconcile source checklist arrays; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
