# EVID-TARGET-COMPOSITION-001 — Validated Target Composition

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free composition boundary
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current Firebase composition root remain
  unchanged
- Claimed target surfaces: `SWIFT-06BA59E1BBDF`, `TEST-952BC24E0233`
- Slice dossier:
  `conversion/implementation-slices/validated-target-composition.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

Phase 1 requires an explicit Supabase/PowerSync composition root after the
environment, operation/readiness and deterministic reference foundations. The
reviewed platform mapping still keeps current Firebase root
`SWIFT-88C69E26FBA0` at `target_mapped`: a provider-free composition contract
does not replace current app construction, instantiate a provider or prove
entry-point integration.

Exactly two new target-only comment scaffolds are claimed. The planned module
will define a closed, typed composition boundary for the ports already present
in `LedgerTargetCore`. Its tests may use `LedgerTargetTestSupport`, but the
production composition module cannot depend on test support and neither module
is linked into the Firebase project.

## Ready-Gate Contract

The dossier freezes five exact architecture requirements and makes all contract
categories explicit. The planned implementation will:

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

## Ready-Gate Verification

The comment-only hashes are acknowledged through the reviewed platform batch
and both surfaces are `target_mapped`. The dossier has no blocker; every
requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. Conversion checking
must pass before behavioral implementation begins.

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
