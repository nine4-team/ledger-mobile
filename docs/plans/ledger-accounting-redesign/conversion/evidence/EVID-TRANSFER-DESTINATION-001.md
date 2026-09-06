# EVID-TRANSFER-DESTINATION-001 — Transfer Destination Selection Contracts

- Timestamp: 2026-09-01
- Class: implementation / provider-free Transfer destination read domain
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-1A05F36246B4`, `TEST-C01243D7B782`
- Slice dossier:
  `conversion/implementation-slices/transfer-destination-selection-contracts.json`
- Verification state: verified at exact implementation commit
  `6dc7d0c21ccd8c966b43b02240d14ad9fe79ea92`
- Implementation hashes:
  - `TransferDestinationSelection.swift`:
    `eb79e780e2391ad1fadd2eb6ce04ae3240af341d433cdabcdde4dc188c82744b`
  - `TransferDestinationSelectionTests.swift`:
    `8b3c09fd7db046e9a28ac561a3d453fc56eb2210bc72057bf7573de0fe458e04`

## Selection and Scope

After verifying Client/Project identity and the canonical Transaction/Transfer
route values, the Phase 1 audit selected the smallest user-meaningful read
boundary that composes them without choosing an open Transfer accounting effect.
D-003/D-005/D-006 and the canonical destination-picker story settle exact
eligibility: another active Project in the same Account with the exact same
ClientID, never the source, Business Inventory, an archived Project, or a name
match.

Exactly two target-only implementation surfaces are claimed in the provider-
free core/test targets. Existing Project pickers, Transfer actions, app/MCP
entry points, backend code and Firebase remain unadvanced. The slice stops
before Item selection, command acceptance, pair writes, D-017 amount, Invoice/
Space/tag/correction/credit effects, schema, provider, source decoding or
migration.

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

## Implemented Contract

`TransferDestinationSelection.swift` now provides:

- exact candidate construction from validated source/destination Project
  summaries and the verified `ProjectTransferRoute`;
- filtering that preserves directory order while excluding the source,
  archived Projects and every different ClientID regardless of equal names;
- source-bound query identity over AccountID, source ProjectID, source ClientID
  and the source-directory fingerprint;
- explicit available, authoritative-no-destination and incomplete-directory
  states with unchanged completeness, quality/readiness, LocalDataVersion and
  as-of evidence;
- decode-through-validation for route/source/destination identity, duplicate
  candidates, completeness, availability and fingerprints; and
- one provider-free local read port plus stable bounded diagnostic codes.

`TransferDestinationSelectionTests.swift` proves deterministic filtering and
order, equal-name/different-Client refusal, source/directory fingerprint changes,
ready/partial/stale availability, canonical restart through an in-memory port,
cross-Account refusal, route/destination mismatch, duplicate candidates,
invalid completeness, source/directory/query tamper, malformed decoding and
every public diagnostic code.

## Local Verification

All commands ran from the dedicated Supabase worktree on 2026-09-01:

- `swift test --package-path LedgeriOS --filter TransferDestinationSelectionTests`
  — pass, 4 tests in 1 suite;
- `swift test --package-path LedgeriOS` — pass, 80 tests in 17 suites;
- `npm run target:environment:check` — pass;
- `npm run target:contracts:check` — pass, including strict TypeScript compile;
- `npm run target:staging:build:macos` — pass;
- `npm run target:staging:build:ios` — pass; and
- `git diff --check` — pass before control-artifact updates.

`DESTINATION-TEST-001` through `DESTINATION-TEST-004` pass with this evidence.

## Immutable Hosted Verification

Exact implementation commit
`6dc7d0c21ccd8c966b43b02240d14ad9fe79ea92` passed both jobs in immutable
[GitHub Actions run 33587234037](https://github.com/nine4-team/ledger-mobile/actions/runs/33587234037):

- `Conversion state and traceability` passed the synchronized conversion,
  authority, slice, query, capability, residual and M0 controls and confirmed
  that checks did not rewrite tracked artifacts; and
- `Isolated target environment` passed the dependency/source-contamination
  boundary, generated app/MCP contract checks, all 80 target tests, macOS and
  generic iOS Simulator builds, and clean-artifact verification.

`DESTINATION-TEST-005`, both claimed surfaces and the dossier are therefore
`verified` at that exact implementation commit. The Node-action deprecation
annotation concerns GitHub's action runtime and did not change or waive any
Ledger check.

## Permanent Limits

This verified projection slice cannot:

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
