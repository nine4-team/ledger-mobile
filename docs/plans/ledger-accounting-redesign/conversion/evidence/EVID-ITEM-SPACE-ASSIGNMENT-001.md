# EVID-ITEM-SPACE-ASSIGNMENT-001 — Item-to-Space Assignment Operation Contracts

- Timestamp: 2026-09-02
- Class: verification / provider-free Item-to-Space assignment intent
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-4B007A00C393`, `TEST-51D893DD949E`
- Slice dossier:
  `conversion/implementation-slices/item-space-assignment-operation-contracts.json`
- Verification state: verified at exact implementation commit
  `c5fdf5c73763b5a629ff0416bebba92696af6581` by immutable Actions run
  `33672006836`
- Ready scaffold hashes:
  - `ItemSpaceAssignmentOperation.swift`:
    `beb965fd5d36a8d73fedbd390d0ff26a6e2ae8ae9af459ceb592f7537db09f5b`
  - `ItemSpaceAssignmentOperationTests.swift`:
    `01a7478e70c6f0c0581791a3842e0b0a51262e26e31417d6995ad50a12af95c5`

## Selection and Scope

The next-slice audit selected direct `AssignItemsToSpace` because canonical
Space authority explicitly requires one durable typed same-scope bulk operation,
and current Firebase behavior issues independent Item writes that may partially
apply. The operation is organizational placement only, so it can be frozen
without choosing occurrence persistence, accounting, Storage, Auth, Postgres or
PowerSync implementation.

The bounded slice owns only one nonempty canonical Item/revision set, one stable
destination Space and exact expected revision, one immutable Project-or-
Business-Inventory scope, deterministic conflict preconditions, the shared
operation lifecycle and one narrow port. It cannot clear placement, change Item
scope, archive a Space, create or update accounting evidence, persist rows, or
wire an application/provider.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/spaces.md` as canonical target authority for stable Space identity,
  same-scope single/bulk assignment, atomic/idempotent application, separate
  scope-changing Item commands and no Space-driven accounting effect;
- `docs/specs/items.md` and the invoice-centered Item lifecycle specifications
  for stable physical Item identity and the rule that Space is independent from
  accounting state;
- the reviewed Spaces capability dossier for independent-write partial failure,
  generic update, stale-scope and duplicate-listener defects plus the typed
  `AssignItemsToSpace` target boundary;
- `02-domain-and-application-architecture.md`, `03-data-sync-and-offline.md` and
  `04-backend-ports-and-adapters.md` for story-specific commands, exact
  preconditions, restart-safe operation evidence and narrow ports; and
- current Space detail/item-assignment callers, `ItemService`, Firebase model/
  repository behavior and existing Space tests as source behavior evidence.

The current app's fire-and-forget field writes, route strings, display names,
nullable scope pairs and SDK acknowledgements are not target contract authority.

## Why Open Decisions Do Not Block This Slice

- O-037 controls what happens to assigned Items when a Space is archived. This
  command cannot archive or delete a Space and therefore does not resolve or
  bypass that policy.
- O-007/O-015 govern hidden occurrence/accounting provenance. Space placement
  is explicitly non-accounting and the payload contains no occurrence, Invoice,
  Transaction, category, amount, price, payer or acquisition value.
- O-023 governs attachment retention; this command carries no attachment.
- O-032 governs posting/review readiness; this command creates no review state.
- A-003/A-004/A-007/A-016 and hosted staging remain proposed/gated. Typed local
  scope and revision evidence are conflict inputs, never provider authorization.

## Ready-Gate Contract

The dossier freezes eight requirements and five verification obligations. It
requires exact Account/actor/contract/Operation identity; one stable destination
Space and immutable Project-or-Business-Inventory scope; exact Space and Item
revisions; a canonical nonempty duplicate-free Item set; deterministic active/
revision/scope preconditions; atomic stable refusal; byte-identical structured
restart; the shared queued/applied/rejected receipt; and one narrow provider-free
`ItemSpaceAssigning` port.

Postgres, handlers, grants, RLS, Sync Streams, Auth, physical local persistence,
optimistic row mutation, app/MCP, media, accounting, migration, observability,
hosted resources and feature activation are explicit nonapplicabilities.

## Dependency Evidence

The Account-discovery verification-document checkpoint is immutable at commit
`4102365871ba3bde9b42e6132f98a02a1bbd3d69`. GitHub Actions run
`33669255726` passed conversion traceability in 9 seconds and the isolated
target environment in 2 minutes 51 seconds, including all 172 then-existing
target tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts.

The verified exact-money/domain-identity, operation-lifecycle, Space creation/
details/checklist and Project Item accounting-section slices supply stable Item,
Space, Project, Account, Principal, revision, scope and receipt primitives. This
slice neither redefines those meanings nor claims their physical adapters.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces
batch and are `target_mapped`. The dossier has no blocker; every requirement is
reciprocally covered by domain, offline-restart, offline-rejection,
deterministic port-flow and exact-commit operational obligations.

The complete local ready gate passes with all 172 existing target tests in
40 suites while the two scaffolds remain comment-only, plus target isolation/
generated contracts, both staging builds, repeatable project generation,
conversion/capability/query/residual controls, M0 and clean formatting. M1/M2
retain exactly their expected 2/164 coverage blockers with zero structural
errors. The synchronized ledger records 787 surfaces / 772 discovered, 361
mapped-or-later target-relevant surfaces, 164 residual surfaces and 43 validated
blockers. Forty-one slices claim 103 of 525 target-relevant surfaces; 86 are
implemented or later. No implementation was allowed to begin before this ready
evidence was committed, pushed and both immutable CI jobs passed.

The exact ready commit
`30f4ab88cd526b89b09dc22f1f26cd66884b0b33` passed immutable GitHub Actions
run `33670383410`: conversion traceability passed in 14 seconds and the isolated
target environment passed in 2 minutes 8 seconds with all 172 then-existing
target tests, graph/generated-contract checks, both staging builds and clean
tracked artifacts. That immutable pass authorized only the frozen provider-free
implementation below.

## Implemented Contract

The bounded implementation now defines:

- `ItemPlacementScope`, exactly one stable Project or Business Inventory scope,
  with one deterministic typed relationship target and no copied name or
  nullable scope pair;
- `ExpectedItemPlacementRevision`, `ItemSpaceAssignmentCandidate` and
  `ItemSpaceAssignmentDraft`, binding one Account, actor, contract, destination
  Space/revision, finite capture time and canonical nonempty duplicate-free
  Item/revision set;
- `AssignItemsToSpacePayload`, containing only destination Space, scope and
  stable Item IDs, plus `AssignItemsToSpaceCommand`, which derives the Space
  subject, exact deterministic Space-active/revision/scope and per-Item
  revision/scope preconditions, fingerprint and receipt validation;
- fail-closed reconstruction for malformed, rebound or tampered scope, draft,
  payload, precondition, subject, fingerprint and receipt evidence through 16
  bounded stable diagnostic codes; and
- one narrow provider-free `ItemSpaceAssigning` port reusing the shared queued,
  exact-replay and changed-intent-refusal lifecycle.

The exact implementation source hashes are:

- `ItemSpaceAssignmentOperation.swift`:
  `7ef831428fc83d66642c460404460e22ee364c8410b384def4b20a5124f529a4`
- `ItemSpaceAssignmentOperationTests.swift`:
  `023122a0906a9b5bf9a485bc629b51d997fcdbebfdcce00ac4a8b9e8ba81fbc1`

## Local Implementation Verification

All four focused Item-to-Space assignment tests pass locally. They cover exact
Project and Business Inventory scope, single and canonical bulk selection,
input-order normalization, complete deterministic preconditions, byte-identical
restart, empty/duplicate/time/rebinding/tamper refusal, all 16 stable diagnostic
codes, exact queued replay, changed-intent rejection and no false receipt from a
failing port.

The complete local implementation gate passes all 176 target tests in 41 suites,
both macOS and generic iOS Simulator staging builds, target isolation/generated
contracts, conversion sync/check/report, capability/query/residual controls, M0
and clean diff formatting. Repeatable XcodeGen output preserves exact project
hash `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and scheme hash
`388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
the source application project is unchanged. M1/M2 retain exactly their expected
2/164 coverage blockers with zero structural errors. The synchronized ledger
still records 787 surfaces / 772 discovered, 361 mapped-or-later target-relevant
surfaces, 164 residual surfaces and 43 validated blockers. Forty-one slices
claim 103 of 525 target-relevant surfaces; 88 are implemented or later. The
exact implementation commit and immutable CI run were the remaining obligation.

The exact implementation commit
`c5fdf5c73763b5a629ff0416bebba92696af6581` passed immutable GitHub Actions run
`33672006836`: conversion traceability passed in 9 seconds and the isolated
target environment passed in 2 minutes 31 seconds. The run repeated all 176
target tests in 41 suites, target isolation and generated-contract checks, both
staging builds and clean tracked-artifact verification. All five dossier
obligations therefore pass, and exactly the two claimed surfaces are verified.

## Permanent Limits

This implementation cannot verify or authorize Item/Space row mutation, physical
offline durability, optimistic presentation, current membership/authorization,
clear assignment, Item scope movement, Space archive/delete, occurrence or
accounting changes, Postgres/RLS/PowerSync, app/MCP integration, Firebase
migration, hosted resources, production access, release or cutover. The source
Firebase application remains unchanged.
