# EVID-SPACE-DETAILS-UPDATE-001 — Space Details Update Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free Space details update
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-EDFA6A1EF8C3`, `TEST-E8832A105D5C`
- Slice dossier:
  `conversion/implementation-slices/space-details-update-operation-contracts.json`
- Verification state: ready locally; executable behavior remains absent until
  the exact comment-only ready commit passes immutable pull-request CI
- Ready scaffold hashes:
  - `SpaceDetailsUpdateOperation.swift`:
    `17d858d85970e165a22db02d9e3b7d3956245be5fd21b9c48eeb4be9941ad9c8`
  - `SpaceDetailsUpdateOperationTests.swift`:
    `f5a877a366877ed95661f043c406981921da8f94cb3878e3eac91f718b127b78`

## Selection and Scope

After verifying direct Space creation, the next dependency audit selected
`UpdateSpaceDetails` as the smallest complete decision-independent operation.
The shipped edit UI preserves name and optional notes, while the reviewed target
capability dossier already separates revisioned details update from creation,
scope, checklists, templates, attachments, Item assignment, review, completion
and archive. The target command therefore owns one complete name-and-notes
replacement for one stable Space and expected revision.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The future command cannot change Project/Inventory scope,
create/revise child state, attach media, assign Items, set completion, archive/
delete a Space or mutate accounting. Firebase source paths, application code,
providers, schema and hosted resources remain unchanged.

## Authority Clarification

`docs/specs/spaces.md` already makes Space identity/scope stable, preserves
duplicate names and optional normalized details, separates typed operations,
and rejects generic backend mechanics as target authority. This checkpoint
makes the already-reviewed update boundary explicit: `UpdateSpaceDetails`
replaces the complete mutable name/optional-notes pair; scope is immutable; and
one expected revision turns stale intent into a conflict instead of a partial
last-write-wins update.

This preserves the shipped edit outcome while correcting its generic Firestore
dictionary and missing revision semantics. It does not add a feature, choose a
backend, deploy anything or affect production.

## Why Open Decisions Do Not Block This Slice

- O-023 governs attachment detach/retention. Details update carries no media.
- O-026 governs shared reference administration. Details update carries no
  template/category/vendor identity or shared reference write.
- O-037 governs assigned Items when an existing Space is archived. Details
  update carries no Item identity, assignment, archive or lifecycle input.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  boundary performs no authorization or physical offline access.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync and
  durable/optimistic implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes eight product/conversion/architecture requirements and
requires:

- one stable Space ID, exact Account, actor, operation contract, Operation ID
  and finite client time;
- one complete outer-whitespace-normalized nonblank name and optional normalized
  notes replacement, with nil/whitespace-only notes meaning absent, interior
  text preserved, duplicate names valid and no unapproved maximum;
- one expected Space revision deriving exactly one same-Space
  `expectedRevision` precondition;
- a typed `UpdateSpaceDetails` intent with no scope/checklist/template/
  attachment/Item/review/completion/lifecycle/accounting/generic-write field;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  semantics;
- canonical decode-through-validation and atomic changed-scope/payload/
  precondition/subject/fingerprint/receipt refusal;
- one narrow provider-free operation port plus deterministic reference/failure
  adapter tests; and
- permanent separation between local command validity and later trusted
  membership/Space/revision authorization and authoritative apply.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, app/MCP, migration, observability and feature activation are
explicit nonapplicabilities.

## Dependency Evidence

The preceding Space-create verification-document checkpoint is immutable:
exact commit `74d411f162633a9fcd03f7976e4b1f312a78473e` passed Actions run
`33650026503`, with conversion traceability in 10 seconds and the isolated
target environment in 2 minutes 28 seconds.

The source/caller/authority mapping is reviewed in
`EVID-CAPABILITY-SPACES-REVIEW-001` and `EVID-M2-SPACES-REVIEW-001`. The verified
Space value normalizers, stable domain IDs and shared operation lifecycle supply
dependencies without authorizing this new command by implication.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces/
review batch and are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The synchronized ledger records 779 surfaces / 764 discovered, 353 mapped-or-
later target-relevant surfaces, 164 residual surfaces and 43 validated blockers.
Thirty-seven slices claim 95 target surfaces and 78 are implementation-advanced.
M0 passes. M1/M2 retain exactly their expected 2/164 prerequisite blockers,
with zero structural errors and the same three explained retired-path warnings.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2/164 prerequisite blockers;
- all 156 existing target tests in 36 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- clean diff formatting.

Passing immutable exact-ready-commit CI may authorize only the bounded
provider-free implementation named here.

## Permanent Limits

This ready plan cannot:

- visibly or authoritatively update any Space;
- create or modify a local/server Space row, revision or audit field;
- change a Space's Project-or-Business-Inventory scope;
- validate Account membership, Space existence/revision or update rights;
- create/revise checklists, apply/save templates, attach/detach media, assign
  Items, create review notes, set completion or archive/delete a Space;
- create/change Transaction, occurrence, Invoice, budget, payer, placement,
  price or any other accounting state;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or optimistic
  projection;
- wire a current/target app edit flow, MCP tool, transport or catalog entry;
- transform or reconcile source Space details; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
