# EVID-SPACE-TEMPLATE-REFERENCE-001 — Space Template Reference Read Contracts

- Timestamp: 2026-09-02
- Class: implementation plan / provider-free Space-template reference read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-77F812A8F463`, `TEST-CB30140F137B`
- Slice dossier:
  `conversion/implementation-slices/space-template-reference-read-contracts.json`
- Verification state: ready; executable implementation and all five obligations
  remain planned
- Ready scaffold hashes:
  - `SpaceTemplateReferenceData.swift`:
    `9682f5d9bbec156fd6c8f92fa0280217622ee19d89ed3198844ad7c69a11dac2`
  - `SpaceTemplateReferenceDataTests.swift`:
    `de2d208b92011112a5e7f777914616a056a3a425b3f185ad9b077857684a8e77`

## Selection and Scope

After verifying vendor-suggestion reference reads, the next Phase 1 dependency
audit selected the Space-template read boundary as the smallest complete
decision-independent dependency. Templates are Account-scoped reusable Space
structure. The target must support real template selection/application later,
but the read value itself must not carry completion state that could recreate
the current `createFromSpace` checked-state-copy defect.

O-026 does not block this read slice. It governs who may create, update,
archive/reactivate or reorder reference data. This boundary receives only
already-authorized local rows for one exact Account and exposes no writer, role,
capability, membership, policy, template-application or Space-creation method.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The Firebase Space-template model/service/settings views and
stub New Space/Save as Template callers remain unchanged and are not target
implementation templates.

## Authority Correction

The dependency audit caught an authority-registry error before executable code:
`docs/specs/spaces.md` already has an explicit target-state notice and states
the corrected template select/apply/save and unchecked-item behavior, but the
crosswalk still labeled it `current_product`. That label would prevent a slice
from using the actual target rule while inviting accidental reliance on the
defective Firebase mechanics.

The ready checkpoint therefore registers `spaces.md` as the sixth canonical
target spec, assigns it as canonical authority to both the Spaces/review and
Project/Client/reference batches, and updates the spec index/control wording.
The generated audit now proves all six registered target specs are used and all
771 conversion surfaces still resolve through one of 18 reviewed batches.
This is an authority classification correction, not a new product decision.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements and
requires:

- stable distinct template, checklist and checklist-item identities with exact
  Account scope, preserved required text, optional notes, active/archive
  lifecycle, revision and explicit deterministic order;
- structure-only checklist items with no `isChecked` or other completion field,
  so template read values cannot carry stale Space progress;
- uniqueness at the documented scope: templates and their presentation order
  in the Account snapshot, checklists and their order within one template, and
  items and their order within one checklist;
- explicit query fingerprint, ready/partial/stale quality, completeness,
  already-authorized visible-row count, local data version and finite as-of
  evidence, including a distinct authoritative-empty state;
- canonical decode-through-validation and byte-identical structured restart;
- atomic refusal for blank required text, cross-Account rows, duplicate
  identity/order, count/time mismatch and malformed evidence; and
- one narrow Account-exact provider-free query port that yields no false
  snapshot on mismatch or failure.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, template writers/O-026 policy, template application/Space
creation, app/MCP, migration, observability and feature activation are explicit
nonapplicabilities.

## Dependency Evidence

The preceding vendor-suggestion verification-document checkpoint is immutable:
exact commit `08cc0472598a5f8171059d91f19f08024a3704f4` passed Actions run
`33632848448`, with conversion traceability in 7 seconds and the isolated target
environment in 2 minutes 58 seconds.

The source/model/caller mapping is already reviewed in
`EVID-CAPABILITY-PROJECT-REFERENCE-001` and
`EVID-M2-PROJECT-REFERENCE-001`. It records stable ordered template definitions,
separates reads from O-026 write authority, identifies the no-op picker/save
callers, and classifies checked-state copying as a defect rather than parity.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, query-port and exact-commit operational obligations.

The synchronized ledger records 771 surfaces, including 756 discovered and 15
retained/manual surfaces. It reports 345 mapped-or-later target-relevant
surfaces, 164 residual surfaces and 43 validated blockers; 33 slices claim 87
target surfaces and 70 are implemented or later. M0 passes. M1 and M2 retain
exactly their expected 2 and 164 blockers.

The complete local ready gate passes:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2 and 164 prerequisite blockers;
- all 140 existing target tests in 32 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds;
- repeatable XcodeGen output with matching
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  target graph hashes and unchanged source-project hash
  `4e76faa4c550a27638b41c69b630ca9d742fa675de68d35d8c9306ee1080d5c4`;
  and
- clean diff formatting.

Exact ready-commit CI remains to be recorded before executable implementation.

## Permanent Limits

This ready plan cannot:

- read, persist, display or authoritatively synchronize a template;
- apply a template, create a Space or allocate target Space/checklist identity;
- create, update, archive, reactivate or reorder template data or resolve O-026;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or durable
  local store;
- wire a picker, management view, save/apply flow, MCP resource/tool, transport
  or catalog;
- transform, backfill or reconcile a Firebase template or source Space; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
