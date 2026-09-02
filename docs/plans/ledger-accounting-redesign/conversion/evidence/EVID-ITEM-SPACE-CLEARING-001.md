# EVID-ITEM-SPACE-CLEARING-001 — Item Space-Assignment Clearing Contracts

- Timestamp: 2026-09-02
- Class: ready gate / provider-free Item Space-clearing intent
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-4C7158974133`, `TEST-0AB198EB6935`
- Slice dossier:
  `conversion/implementation-slices/item-space-clearing-operation-contracts.json`
- Verification state: ready locally; exact ready-commit CI is required before
  executable behavior may be added
- Ready scaffold hashes:
  - `ItemSpaceClearingOperation.swift`:
    `a5580c3efb9fa0e8569bc2813b4545e13b65a585bd1f6c842b6f2856e690a42c`
  - `ItemSpaceClearingOperationTests.swift`:
    `04724d17f1fd927c8734e5fe7e7372c702fb612f59464f2cf44e9ad47e295a41`

## Selection and Scope

The next-slice audit selected explicit Item Space clearing because canonical
Space authority already requires single/bulk clear through a durable typed
operation and D-023 makes Space placement independent from accounting. It is
the direct complement to the verified assignment operation and requires no
choice about occurrence persistence, Invoice behavior, Space archive policy,
attachment deletion, Auth, Postgres or PowerSync implementation.

The current app sends generic `spaceId: NSNull()` dictionaries from Item,
Inventory, Project, Space and universal-search screens. `ItemsService` silently
deduplicates Item IDs, derives old-Space image-checkmark cleanup, and splits
large write sets into independent Firestore batches, so one requested clear can
partially apply. Those mechanics are source evidence, not target contracts.

The bounded target slice owns only one canonical nonempty Item/revision/current-
Space set in one immutable Project-or-Business-Inventory scope, deterministic
conflict preconditions, the shared operation lifecycle and one narrow port. One
selection may contain different current Spaces. The later handler derives and
closes affected green Item-linked Space-photo checkmark relationships without
accepting marker data from the client or deleting media bytes.

## Product and Source Cross-Reference

The audit cross-referenced:

- `docs/specs/spaces.md` for optional placement, single/bulk clear, same-scope
  validation, atomic/idempotent application, checkmark closure and accounting
  independence;
- `docs/specs/proto-item-capture.md` and D-019/D-023 for one physical Item and
  the rule that changing Space cannot change Accounted For state;
- the reviewed Spaces dossier for generic-null and multi-batch partial-failure
  defects plus the typed clear target boundary;
- the reviewed media dossier for preserving Item-linked photo marks while
  replacing URL-shaped identity and separating reference removal from byte
  deletion;
- `02-domain-and-application-architecture.md`, `03-data-sync-and-offline.md` and
  `04-backend-ports-and-adapters.md` for story-specific commands, exact
  preconditions, restart-safe operation evidence and narrow ports; and
- current Item/Inventory/Project/Space/Search clear callers, `ItemsService`,
  image-checkmark calculations and integration tests as source behavior
  evidence.

The target command does not preserve caller-authored nulls, field dictionaries,
Firestore batch limits, URL identity, optimistic false success, silent duplicate
removal or SDK acknowledgements.

## Why Open Decisions Do Not Block This Slice

- O-037 controls what archiving a Space does to existing Item assignments. This
  command cannot archive/delete a Space and expresses only a separate explicit
  user-requested clear; it does not silently clear as an archive side effect.
- O-023 controls reference and permanent byte deletion. Closing an Item-linked
  photo-mark relationship deletes neither the Space photo reference nor bytes,
  and the client carries no destructive media instruction.
- O-007/O-015 govern hidden occurrence/accounting provenance. Space clearing is
  explicitly non-accounting and carries no Transaction, occurrence, Invoice,
  category, amount, price, payer or acquisition value.
- A-003/A-004/A-016 and hosted staging remain proposed/gated. Typed local scope,
  revision and current-placement evidence are conflict inputs, never provider
  authorization.

## Ready-Gate Contract

The dossier freezes eight requirements and five verification obligations. It
requires exact Account/actor/contract/Operation identity; one immutable Project-
or-Business-Inventory scope; a canonical nonempty duplicate-free Item/revision/
current-Space set that may span multiple source Spaces; deterministic distinct-
Space scope plus per-Item revision/scope/current-placement preconditions; atomic
stable refusal; byte-identical structured restart; the shared queued/applied/
rejected receipt; and one narrow provider-free
`ItemSpaceAssignmentClearing` port.

Marker cleanup is a later authoritative derived effect. Postgres, handlers,
grants, RLS, Sync Streams, Auth, physical local persistence, optimistic row or
marker mutation, app/MCP, media-byte lifecycle, accounting, migration,
observability, hosted resources and feature activation are explicit
nonapplicabilities.

## Dependency Evidence

The verified assignment operation supplies the shared placement scope and
operation semantics. Its exact implementation commit
`c5fdf5c73763b5a629ff0416bebba92696af6581` passed immutable Actions run
`33672006836` with conversion traceability in 9 seconds and the isolated target
environment in 2 minutes 31 seconds, including all 176 target tests in 41
suites, graph/contracts, both builds and clean artifacts.

Its verification-document commit
`6ff51992726a7a2d88739bf9e8a689bffe4b6de4` passed immutable Actions run
`33672821325`: traceability passed in 8 seconds and the isolated target passed in
3 minutes 5 seconds with all 176 then-existing target tests, both builds and
clean tracked artifacts.

Verified exact-money/domain-identity, operation-lifecycle, attachment-capture,
Space and Project Item accounting-section slices supply reusable IDs, receipt
and independence primitives. This slice neither redefines them nor claims
physical adapters.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Spaces
batch and are `target_mapped`. The dossier has no blocker; every requirement is
reciprocally covered by domain, offline-restart, offline-rejection,
deterministic port-flow and exact-commit operational obligations.

The complete local ready gate passes with all 176 existing target tests in
41 suites while the two scaffolds remain comment-only, plus target isolation/
generated contracts, both staging builds, repeatable project generation,
conversion/capability/query/residual controls, M0 and clean formatting. M1/M2
retain exactly their expected 2/164 coverage blockers with zero structural
errors. The synchronized ledger records 789 surfaces / 774
discovered, 363 mapped-or-later target-relevant surfaces, 164 residual surfaces
and 43 validated blockers. Forty-two slices claim 105 of 527 target-relevant
surfaces; 88 remain implemented or later. Repeatable XcodeGen output preserves
exact project hash
`0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
and scheme hash
`388303af0f4bd6641d70c669ff3754445ab4f59c1a5310cdfe69336827990ed8`;
the source application project is unchanged. No implementation may begin before
this ready evidence is committed, pushed and both immutable CI jobs pass.

## Permanent Limits

This ready evidence cannot verify or authorize Item/Space/marker row mutation,
physical offline durability, optimistic presentation, current membership/
authorization, destination assignment, Item scope movement, Space archive/
delete, attachment reference or byte deletion, occurrence or accounting
changes, Postgres/RLS/PowerSync, app/MCP integration, Firebase migration, hosted
resources, production access, release or cutover. The source Firebase
application remains unchanged.
