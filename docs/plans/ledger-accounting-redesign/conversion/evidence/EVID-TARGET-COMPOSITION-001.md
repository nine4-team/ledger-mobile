# EVID-TARGET-COMPOSITION-001 — Validated Target Composition

- Timestamp: 2026-09-01
- Class: implementation / provider-free composition boundary
- Exact implementation commit:
  `be88c5b9e42eef90018f84012f5a3e60f9631009` on
  `codex/supabase-powersync-implementation`
- Immutable hosted CI:
  [GitHub Actions run 33581326840](https://github.com/nine4-team/ledger-mobile/actions/runs/33581326840),
  both jobs passed
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current Firebase composition root remain
  unchanged
- Claimed target surfaces: `SWIFT-06BA59E1BBDF`, `TEST-952BC24E0233`
- Slice dossier:
  `conversion/implementation-slices/validated-target-composition.json`
- Slice state: verified; all four obligations pass

## Selection and Scope

Phase 1 requires an explicit Supabase/PowerSync composition root after the
environment, operation/readiness and deterministic reference foundations. The
reviewed platform mapping still keeps current Firebase root
`SWIFT-88C69E26FBA0` at `target_mapped`: a provider-free composition contract
does not replace current app construction, instantiate a provider or prove
entry-point integration.

Exactly two target-only implementation surfaces are claimed. The separate
module defines a closed, typed composition boundary for the ports already
present in `LedgerTargetCore`. Its tests use `LedgerTargetTestSupport`, while
the production composition module depends only on core and neither module is
linked into either application project.

## Ready-Gate Contract

The dossier freezes five exact architecture requirements and makes all contract
categories explicit. The implementation:

- bind one composition use, exact validated environment persistence identity,
  catalog versions and stable dependency descriptors;
- own the currently available contract-catalog, operation-query and sync-health
  capabilities exactly once through typed ports rather than a service locator;
- refuse missing, duplicate, cross-environment, incompatible, unknown, gated,
  deprecated or multiply-owned capability wiring before returning a composed
  value;
- prevent test-reference dependencies from entering application-runtime
  composition;
- emit bounded canonical structural receipt evidence that restores offline but
  cannot recreate or authorize adapters; and
- remain provider-free, database-free, transport-free and absent from current
  app/MCP authority.

Postgres, handlers, Data API, RLS, PowerSync Streams, Storage/media, concrete
app/MCP wiring, migration and observability are explicitly out of scope rather
than silently omitted. Successful composition will prove structure only, not
authorization, synchronization, local durability, hosted readiness or provider
fidelity.

## Implemented Contract

`LedgerTargetComposition/ValidatedTargetComposition.swift` now provides:

- a closed `TargetCompositionPlan` over one exact validated environment
  persistence binding, composition use, catalog/contract versions and the
  complete catalog/operation-query/sync-health dependency set;
- stable bounded dependency implementation IDs, exact dependency classes and
  sorted one-owner capability sets with explicit reference-versus-runtime use;
- a typed `TargetCompositionAssembler` that exposes only
  `ContractCatalogProviding`, `OperationQuerying` and `SyncHealthProviding`
  after exact descriptor, catalog-version and available-capability closure;
- stable refusal for incomplete, duplicate, wrong-key, wrong-implementation,
  cross-environment, wrong-use/class, unavailable/deprecated/duplicate/unowned
  capability, catalog, evidence, canonical, digest and size failures; and
- a structural-only `TargetCompositionReceipt` with bounded sorted-key JSON,
  SHA-256 content binding and restore-through-plan revalidation. The receipt
  cannot reconstruct an adapter or claim authorization, synchronization,
  durability, provider fidelity or deployment readiness.

`LedgerTargetComposition` is a separate package product depending only on
`LedgerTargetCore`. Its tests depend only on core, composition and
`LedgerTargetTestSupport`. The graph guard scans both new directories for
provider imports and rejects the composition module from the staging and
Firebase application projects.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter ValidatedTargetCompositionTests`:
  pass, three tests;
- `swift test --package-path LedgeriOS`: pass, 66 tests across thirteen suites;
- `npm run target:environment:check`: pass; exact package edges, provider-import
  scan and application/source-project exclusion are valid;
- `npm run target:contracts:check`: pass; generated Swift/TypeScript/MCP
  contract projections remain current;
- `npm run target:staging:build:macos`: pass; and
- `npm run target:staging:build:ios`: pass for generic iOS Simulator.

The tests exercise actual configured catalog, operation-query and sync-health
ports; canonical restart/input-order equivalence; and atomic refusal for
missing/duplicate/wrong/cross-environment/reference-runtime dependencies,
version drift, gated/deprecated/duplicate/unowned capabilities, unsafe evidence,
digest tamper, noncanonical bytes and oversized evidence.

`COMPOSE-TEST-001`, `COMPOSE-TEST-002` and `COMPOSE-TEST-003` pass locally.
`COMPOSE-TEST-004` passed in immutable GitHub Actions run `33581326840` on exact
implementation commit `be88c5b9e42eef90018f84012f5a3e60f9631009`:
conversion traceability, graph/generated-contract checks, all 66 target tests,
both target builds and clean tracked artifacts passed. The slice and exactly
its two target-only surfaces are therefore `verified`.

## Ready-Gate Verification

The original comment-only hashes were acknowledged through the reviewed
platform batch before implementation. The dossier has no blocker; every
requirement remains reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. The current
implementation hashes are separately acknowledged only after code and local
verification review.

## Permanent Limits

This ready gate and later composition contract cannot:

- select or approve Auth, Supabase, PowerSync, Storage or deployment topology;
- implement a provider adapter, local database, Sync Stream, server handler,
  RLS policy or product operation;
- activate a product feature from structural capability registration;
- claim current Firebase root replacement or concrete app/MCP parity;
- read Firebase, import an export, contact hosted services or use production
  credentials; or
- authorize migration, deployment, release or cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
