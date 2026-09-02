# EVID-TRANSACTION-TAXONOMY-001 — Transaction Taxonomy and Transfer Identity

- Timestamp: 2026-09-01
- Class: implementation / provider-free Transaction domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-C7C58265EA19`, `TEST-28D11BDABC0A`
- Slice dossier:
  `conversion/implementation-slices/transaction-taxonomy-and-transfer-identity.json`
- Implementation state: implemented locally; exact-commit hosted CI remains
  required before verification
- Implementation hashes:
  - `TransactionTaxonomy.swift`:
    `63c7836292efe4211e8ed7b5cf8d5ac446b05daf1df94bfc44f9c6689430e54f`
  - `TransactionTaxonomyTests.swift`:
    `ba3e2bc22208c6fefc8c6c895fbf91135c42f842e04042c326a46eaf5ff10064`

## Selection and Scope

After verifying Client/Project identity, the Phase 1 audit selected the smallest
confirmed accounting boundary that can use it without choosing an open money,
occurrence or provider policy. D-001/D-002/D-007 settle the exact global
Purchase/Return/Transfer set and scope-owner meaning. D-003–D-006 settle that a
Transfer is direct, project-only, same-Account/same-Client and structurally
paired. These values are prerequisites for later Transaction reads, commands,
schema constraints, migration classification and app/MCP contracts, and must not
be redefined independently in those layers.

Exactly two target-only implementation surfaces are claimed in the existing
provider-free core/test targets. Existing Transaction models, services, UI,
Functions, rules, MCP tools and Firebase code remain unadvanced. The slice stops
before money amount/sign, Item lines, paid/open allocation, Invoice/Space effects,
correction, lifecycle, schema, provider, legacy decoding or migration. D-017 and
O-002/O-011–O-015/O-028–O-032 therefore remain untouched.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- a closed three-value target Transaction type with derived economic meaning;
- an explicit Business Inventory owner or Account/Project/Client project scope;
- standalone Purchase/Return and source/destination Transfer roles that cannot
  be combined incompatibly;
- a direct Transfer route derived from exact Project/Client identities, with a
  distinct source, active destination and no name-based authority;
- one operation/correlation-bound pair with distinct source/destination
  Transaction IDs; and
- deterministic restart/refusal proof with no provider, state, source transform
  or application integration.

Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP wiring,
migration, observability and feature activation are explicit
non-applicabilities. Later vertical slices remain responsible for authoritative
pair writes, atomicity, server authorization, offline download completeness and
the full accounting effects.

## Implemented Contract

`TransactionTaxonomy.swift` now provides:

- the exact `purchase`, `return`, and `transfer` set, with unknown encoded values
  rejected;
- validated Business Inventory and Project scopes over typed Account, Project,
  and Client identities;
- standalone Purchase/Return roles and source/destination Transfer roles, with
  economic meaning derived exclusively from the canonical type;
- an exact-ID direct Project route requiring one Account, one Client, distinct
  Projects, and an active destination while retaining no display-name evidence;
- a pair identity binding one Operation ID, one validated route, and distinct
  source/destination Transaction IDs; and
- decode-through-construction validation plus stable bounded diagnostic codes.

`TransactionTaxonomyTests.swift` proves the exact valid set, scope-relative
meaning, same-name/different-Client refusal, all route boundaries, distinct pair
identity, canonical byte-identical restart, malformed aggregate decoding, and
every public diagnostic code. The provider-free values neither authorize a user
nor persist or write a Transaction.

## Local Verification

All commands ran from the dedicated Supabase worktree on 2026-09-01:

- `swift test --package-path LedgeriOS --filter TransactionTaxonomyTests` — pass,
  4 tests in 1 suite;
- `swift test --package-path LedgeriOS` — pass, 76 tests in 16 suites;
- `npm run target:environment:check` — pass;
- `npm run target:contracts:check` — pass, including strict TypeScript compile;
- `npm run target:staging:build:macos` — pass;
- `npm run target:staging:build:ios` — pass; and
- `git diff --check` — pass before control-artifact updates.

`TAXONOMY-TEST-001` through `TAXONOMY-TEST-004` pass with this evidence.
`TAXONOMY-TEST-005` remains planned until the exact committed implementation
passes the immutable pull-request conversion and isolated-target jobs. Both
claimed surfaces and the dossier therefore advance only to `implemented`.

## Permanent Limits

This ready gate and later value implementation cannot:

- interpret a pending credit, physical move, Expense, Fee, Invoice line or
  legacy enum as a canonical Transaction;
- create a Transaction, Transfer pair, Item movement, budget contribution,
  Invoice effect or correction;
- choose amount/sign/category/line/Space/history/posting/lifecycle semantics or
  any open product decision;
- expose or authorize server rows, define RLS/Sync Streams or claim physical
  offline behavior;
- parse or migrate Firebase Transaction fields or claim source reconciliation;
- wire current app/MCP entry points or alter either application project; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
