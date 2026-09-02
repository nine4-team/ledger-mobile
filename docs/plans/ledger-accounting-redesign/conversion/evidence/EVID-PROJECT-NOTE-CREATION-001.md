# EVID-PROJECT-NOTE-CREATION-001 — Project Note Creation Operation Contracts

- Timestamp: 2026-09-02
- Class: implementation planning / provider-free Project-note creation command
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-9CDB2BCAC71B`, `TEST-DB2559406D3D`
- Slice dossier:
  `conversion/implementation-slices/project-note-creation-operation-contracts.json`
- Verification state: implemented; four local obligations pass and exact-
  implementation-commit CI remains planned
- Ready scaffold hashes:
  - `ProjectNoteCreationOperation.swift`:
    `18a49e7175ac8a112ac1c7301e1797e09945fd1168815079dd6322c54a7c47cd`
  - `ProjectNoteCreationOperationTests.swift`:
    `f441ddcf4c3044dbb4807c61c80ce239c861547ef5790faea8251b761219196a`

## Selection and Scope

After verifying the bounded Project-note read contract, the remaining Phase 1
Project/Client/reference dependency audit selected note creation as the next
smallest complete user operation. The reviewed capability contract already
settles stable offline-allocatable note identity, nonblank note content,
authorship/source preservation, shared durable operation identity and the rule
that retry cannot duplicate a note. The M2 mapping also requires an exact
Project parent preflight before authoritative creation.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. The slice defines the typed intent needed by a later shared app/
MCP handler, but does not implement that handler. Existing Firebase note
mechanics, the shipped Notes UI, MCP tools, edit/remove behavior, schema, Auth,
RLS, Sync, migration and production remain unadvanced.

## Authority and Audit Boundary

- D-006 supplies stable Account/Project identity and prevents display text from
  becoming relationship or authorization evidence.
- The reviewed Project/Client/reference dossier requires stable note identity,
  deterministic shared operations, immutable creator/creation evidence and no
  duplicate retry.
- The shared operation envelope defines `actorPrincipalId` as audit intent that
  the server derives and verifies from authentication, and `clientCreatedAt` as
  UX evidence rather than server ordering.
- The payload may preserve a typed `requestedSource` for local intent and app/
  MCP parity, but it cannot establish the final authoritative note source.
- Creator display, authoritative creation time, revision, edit audit and
  deletion evidence are excluded from the command. A later trusted handler must
  assign final audit/source evidence and preflight exact Project existence and
  visibility without revealing whether an unavailable parent is missing or
  denied.

This boundary lets disconnected clients preserve the complete user intent
without allowing serialized client input to masquerade as authoritative audit
evidence.

## Why Open Decisions Do Not Block This Slice

- O-024 governs physical Project deletion, not adding text to an available
  Project. No delete behavior is created.
- O-025 governs Client correction and Project reassignment. The command carries
  no Client identity, name or relationship mutation.
- O-026 governs shared reference-data mutation, not Project notes.
- Note edit/remove role and revision policy are intentionally outside this
  create-only slice.
- A-007/A-016 govern Auth correlation and offline authorization duration. This
  contract carries typed Account/actor intent but performs no authorization.
- A-003/A-004/A-015 and physical verification govern provider schema, Sync,
  optimistic projection and durable implementation, all excluded here.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements
and requires:

- one preallocated stable ProjectNoteID bound to exact Account and Project
  identity, nonblank text and a typed requested source;
- one typed `AddProjectNote` story with no generic update fields, edit/remove
  behavior, Project/Client display identity or backend type;
- explicit separation between client actor/time/source intent and later trusted
  creator/time/final-source evidence;
- one derived parent Project reference sufficient for the later authoritative
  existence/visibility preflight, with no caller-authored authorization claim;
- reuse of the shared operation envelope, fingerprint, receipt and exact replay
  lifecycle rather than a note-specific queue/result model;
- canonical decode-through-validation and atomic changed-scope/payload/parent/
  precondition/fingerprint/receipt refusal; and
- one narrow provider-free create port plus deterministic reference/failure
  adapter tests.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, optimistic note rows, media, app/MCP wiring, migration,
observability and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, operation-idempotency and exact-commit operational obligations.

The ready checkpoint passed from the dedicated Supabase worktree:

- conversion sync/check/report and capability/query/residual controls;
- M0, with M1/M2 retaining their expected prerequisite blockers;
- all 124 existing target tests in 28 suites while the two scaffolds contain no
  executable Project-note-creation behavior;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds; and
- XcodeGen/source-project stability plus `git diff --check`.

The synchronized ledger records 763 surfaces, including 748 currently
discovered. It reports 337 of 501 target-relevant surfaces mapped or later, 164
residual surfaces and 43 validated blockers. M0 passes; M1 and M2 retain exactly
their expected 2 and 164 blockers. Only the three documented retired-path
warnings remain.

Passing this local ready gate authorizes only the bounded provider-free
implementation named in the dossier. Exact-commit CI remains required and will
be attached after the ready checkpoint is pushed.

Exact ready commit d84dc10998981b54c847b112cf1e063bd1e74c29
passed immutable GitHub Actions run
[33620363089](https://github.com/nine4-team/ledger-mobile/actions/runs/33620363089):
conversion traceability passed in 11 seconds and the isolated-target job passed
in 3 minutes 33 seconds with all 124 then-existing tests, graph/generated-
contract checks, macOS and generic iOS Simulator builds and clean tracked
artifacts.

## Implemented Contract

ProjectNoteCreationOperation.swift now provides:

- ProjectNoteCreationDraft, which binds one preallocated ProjectNoteID,
  nonblank text and requested source to exact Account, actor, operation-
  contract, Project and finite client capture-time intent;
- AddProjectNotePayload, which contains only ProjectID, ProjectNoteID,
  ProjectNoteText and requestedSource;
- AddProjectNoteCommand, whose public construction creates a precondition-free
  shared OperationEnvelope, derives the exact parent Project reference and
  operation fingerprint, and whose decoder revalidates every duplicated binding
  rather than trusting serialized derived evidence;
- exact OperationReceipt validation for the command's OperationID;
- the narrow ProjectNoteCreating provider-free port; and
- a closed stable failure taxonomy for invalid client time, scope/actor/
  contract/payload/precondition/parent/fingerprint/receipt mismatch, malformed
  command evidence and local acceptance failure.

Creator display, authoritative creation time, revision, edit audit, deletion
state and authorization claims are absent. actorPrincipalId,
clientCreatedAt and requestedSource remain intent/evidence for a later trusted
handler to verify or resolve; none becomes authoritative merely because the
command is valid or locally queued.

Implementation hashes:

- ProjectNoteCreationOperation.swift:
  bd9f1a1351f22276fef8322627ee99344855761de1a91803adac6032970217d5
- ProjectNoteCreationOperationTests.swift:
  38b3d2fc20ef768b572ba95f96431e967bc26ed4a756c5b20dcf3f4f0aae1740

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact command/payload/parent
shape and excluded authoritative audit; byte-identical canonical restart;
stable refusal of blank text, malformed source, invalid time, rebound Account/
actor/contract/Project/note/text/source/parent/precondition/fingerprint/receipt
evidence; exact OperationJournal replay/mismatch behavior; and no false receipt
from a failing port.

The complete local gate passes with all 128 target tests in 29 suites, target
environment isolation, generated app/MCP contracts, macOS and generic iOS
Simulator staging builds, conversion/capability/query/residual controls, M0 and
clean diff formatting. M1/M2 retain exactly their expected 2/164 blockers.

PROJECTNOTECREATE-TEST-001 through -004 therefore pass. Exact-
implementation-commit hosted PROJECTNOTECREATE-TEST-005 remains planned, so
exactly the two claimed target surfaces are implemented, not verified.

## Permanent Limits

This ready plan cannot:

- create, project, search or display a local/server Project-note row;
- authorize Account membership or Project visibility;
- establish caller-supplied creator, authoritative timestamp, final source,
  revision, edit audit or deletion evidence;
- edit or remove a note or decide mutation roles/conflict policy;
- define a Postgres table/index, handler, grant, RLS policy, Sync Stream or
  optimistic projection;
- wire the Notes tab, Project context/service, MCP tool, transport or catalog;
- decode, merge, deduplicate, quarantine or reconcile Firebase embedded/nested
  notes; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
