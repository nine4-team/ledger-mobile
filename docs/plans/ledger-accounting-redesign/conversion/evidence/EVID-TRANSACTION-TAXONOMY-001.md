# EVID-TRANSACTION-TAXONOMY-001 — Transaction Taxonomy and Transfer Identity

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Transaction domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-C7C58265EA19`, `TEST-28D11BDABC0A`
- Slice dossier:
  `conversion/implementation-slices/transaction-taxonomy-and-transfer-identity.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

After verifying Client/Project identity, the Phase 1 audit selected the smallest
confirmed accounting boundary that can use it without choosing an open money,
occurrence or provider policy. D-001/D-002/D-007 settle the exact global
Purchase/Return/Transfer set and scope-owner meaning. D-003–D-006 settle that a
Transfer is direct, project-only, same-Account/same-Client and structurally
paired. These values are prerequisites for later Transaction reads, commands,
schema constraints, migration classification and app/MCP contracts, and must not
be redefined independently in those layers.

Exactly two target-only comment scaffolds are claimed in the existing
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

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed Inventory/
Transaction batch and both surfaces are `target_mapped`. The dossier has no
blocker; every requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. Conversion checking
must pass before behavioral implementation begins.

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
