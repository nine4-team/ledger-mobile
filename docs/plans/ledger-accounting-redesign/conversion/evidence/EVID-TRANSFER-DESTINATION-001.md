# EVID-TRANSFER-DESTINATION-001 — Transfer Destination Selection Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free Transfer destination read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-1A05F36246B4`, `TEST-C01243D7B782`
- Slice dossier:
  `conversion/implementation-slices/transfer-destination-selection-contracts.json`
- Ready-gate state: ready; behavior and executable self-tests are not yet
  implemented

## Selection and Scope

After verifying Client/Project identity and the canonical Transaction/Transfer
route values, the Phase 1 audit selected the smallest user-meaningful read
boundary that composes them without choosing an open Transfer accounting effect.
D-003/D-005/D-006 and the canonical destination-picker story settle exact
eligibility: another active Project in the same Account with the exact same
ClientID, never the source, Business Inventory, an archived Project, or a name
match.

Exactly two target-only comment scaffolds are claimed in the provider-free core/
test targets. Existing Project pickers, Transfer actions, app/MCP entry points,
backend code and Firebase remain unadvanced. The slice stops before Item
selection, command acceptance, pair writes, D-017 amount, Invoice/Space/tag/
correction/credit effects, schema, provider, source decoding or migration.

## Ready-Gate Contract

The dossier freezes six exact canonical/architecture requirements and requires:

- a candidate that binds one destination Project to the already-validated exact
  `ProjectTransferRoute`;
- source-bound filtering over a validated local Project directory using only
  AccountID, ClientID, ProjectID and destination lifecycle;
- preservation of deterministic directory order and source/directory query
  fingerprints, completeness, quality, LocalDataVersion and as-of evidence;
- distinct available, authoritative-no-destination and incomplete-directory
  states;
- canonical restart and atomic tamper/refusal behavior; and
- one small backend-neutral local read port with no write or provider surface.

Postgres, handlers, Data API, RLS, Sync Streams, media, concrete app/MCP wiring,
migration, observability and feature activation are explicit nonapplicabilities.
A locally offered route never substitutes for current server authorization and
does not create or queue a Transfer.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed Inventory/
Transaction batch and both surfaces are `target_mapped`. The dossier has no
blocker; every requirement is reciprocally covered by domain, offline-restart,
offline-rejection and exact-commit operational obligations. Conversion checking
must pass before behavioral implementation begins.

## Permanent Limits

This ready gate and later projection implementation cannot:

- authorize a Principal or prove current membership/financial visibility;
- create a Transaction, Transfer pair, Item move, Invoice effect, payment,
  refund, credit, budget contribution or correction;
- choose Items or amount/category/Space/tag/history/lifecycle semantics;
- define RLS, Sync Streams, local persistence or physical offline behavior;
- parse or migrate Firebase Project/clientName data;
- wire the current picker or MCP transport; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
