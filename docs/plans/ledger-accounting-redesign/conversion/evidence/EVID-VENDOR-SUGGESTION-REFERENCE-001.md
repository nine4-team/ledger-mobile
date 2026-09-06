# EVID-VENDOR-SUGGESTION-REFERENCE-001 — Vendor Suggestion Reference Read Contracts

- Timestamp: 2026-09-02
- Class: verification / provider-free vendor-suggestion reference read
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and shipped app remain unchanged
- Claimed target surfaces: `SWIFT-111A94B464D5`, `TEST-A73A49564E8C`
- Slice dossier:
  `conversion/implementation-slices/vendor-suggestion-reference-read-contracts.json`
- Verification state: verified; all five obligations pass at exact implementation
  commit `519b4338c7cbe8cc63a01820116bef5283a8625a`
- Ready scaffold hashes:
  - `VendorSuggestionReferenceData.swift`:
    `463c20fe2a864a3b71cdb06bc62990ea1463c61220039470a0b11fe50cd316c1`
  - `VendorSuggestionReferenceDataTests.swift`:
    `d183163d42499c3164b2ae3e564ccd09013158a25bca514b55423842e831c786`

## Selection and Scope

After verifying current-Principal Project preference update, the next Phase 1
Project/Client/reference dependency audit selected the vendor-suggestion read
boundary as the smallest complete decision-independent dependency. Product and
architecture authority agree that Vendor/Source remains captured free text on
its owning Item, Expense or Transaction; a reusable suggestion is ordered
convenience data with stable identity and cannot become Vendor or accounting
identity.

O-026 does not block this read slice. It governs suggestion creation, rename,
merge, archive/reactivation, reorder and the capabilities that authorize those
mutations. This slice receives only already-authorized local rows for one exact
Account and exposes no writer, role, capability, membership or policy decision.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test roots. Existing Firebase vendor-default services, settings, pickers,
rules, seeded defaults and source records remain unchanged and are not treated
as replaced by this contract.

## Ready-Gate Contract

The dossier freezes seven exact product/conversion/architecture requirements and
requires:

- stable typed suggestion identity, exact Account scope, preserved bounded
  display spelling, normalized comparison, active/archive lifecycle, unique
  presentation order and revision;
- deterministic ordered results and active selectable source strings with no
  Vendor, Item, Expense, Transaction, money, category or relationship identity;
- explicit query fingerprint, ready/partial/stale quality, completeness,
  visible-row count, local data version and finite as-of evidence, including a
  distinct authoritative-empty state;
- canonical decode-through-validation and byte-identical structured restart;
- atomic refusal for invalid values, cross-Account rows, duplicate identity/
  normalized value/order, count/time mismatch and malformed evidence; and
- one narrow Account-exact provider-free query port that yields no false
  snapshot on mismatch or failure.

Postgres, handlers, Data API grants, RLS, Sync Streams, physical local
persistence, default seeding, mutation/O-026 policy, picker composition,
app/MCP, migration, observability and feature activation are explicit
nonapplicabilities.

## Dependency Evidence

The preceding Project preference update verification-document checkpoint is
immutable: exact commit `da5cfa4a5ad8941656475644202b510c1ee593ad`
passed Actions run `33629389877`, with conversion traceability in 8 seconds and
the isolated target environment in 2 minutes 32 seconds.

The source/model/picker mapping is already reviewed in
`EVID-CAPABILITY-PROJECT-REFERENCE-001` and
`EVID-M2-PROJECT-REFERENCE-001`. It preserves source spelling/order, requires
stable revisioned target entries and one local reference snapshot, separates
read access from O-026 mutation authority, and forbids turning selection into
canonical Vendor identity or rewriting historical source text.

## Ready-Gate Verification

The two comment-only surfaces are acknowledged through the reviewed Project/
Client/reference batch and are `target_mapped`. The dossier has no blocker;
every requirement is reciprocally covered by domain, offline-restart, offline-
rejection, reference-port and exact-commit operational obligations.

The complete local ready gate passes:

- conversion sync/check and capability/query/residual controls;
- M0, with M1/M2 retaining their expected 2 and 164 prerequisite blockers;
- all 136 existing target tests in 31 suites while both scaffolds remain
  comment-only;
- target environment and generated app/MCP contract checks;
- macOS and generic iOS Simulator staging builds;
- repeatable XcodeGen output with matching
  `0657194a678ebbeb7d55e322303e2c5d63198f342e090d2f7072525b20ff9f53`
  graph hashes and no source-project diff; and
- clean diff formatting.

The synchronized ledger records 769 surfaces, including 754 discovered and 15
manual surfaces. It reports 343 mapped target-relevant surfaces, 164 residual
surfaces and 43 validated blockers; 32 slices claim 85 target surfaces and 68
are implemented or later. No product or provider gate was silently cleared.

Exact ready commit `3abee18e8011943e74185e43d1630aeb9fa2bff7`
passed immutable GitHub Actions run `33631062466`: conversion traceability
passed in 20 seconds and the isolated target environment passed in 2 minutes
51 seconds with all 136 then-existing tests, graph/generated-contract checks,
macOS and generic iOS Simulator staging builds and clean tracked artifacts. That
gate authorized only the bounded provider-free implementation named here.

## Implemented Contract

- `VendorSuggestionID` is stable typed identity, while
  `VendorSuggestionDisplayValue` preserves accepted case/internal spacing,
  derives whitespace-collapsed lowercase comparison, and refuses empty,
  control-character or over-200-byte values.
- `VendorSuggestionSnapshot` binds exact Account, display value, active/archive
  lifecycle, unique presentation order and revision. `sourceSnapshot` returns
  only the preserved string; it cannot become Vendor or accounting identity.
- `VendorSuggestionReferenceSnapshot` verifies finite local evidence, exact
  Account scope, already-authorized visible count and unique identity/normalized
  value/order, then provides deterministic order and active-only selectable
  source strings.
- `VendorSuggestionQuerying` is the narrow provider-free Account read port, and
  `VendorSuggestionReferenceFailure` supplies stable bounded value/scope/
  duplicate/count/time/local-read/encoding diagnostics.

Implementation hashes:

- VendorSuggestionReferenceData.swift:
  `74c6498bf389803c4af562d55d4b3d02d15aa2449f8761ddc0519df0538bf22d`
- VendorSuggestionReferenceDataTests.swift:
  `fb9f247ee1728ee2bad0e35a24938528edd1c2810f068614e7d313dff64f3fb5`

## Local Implementation Verification

Four focused deterministic tests pass. They prove exact stable ID/Account/
display/lifecycle/order/revision shape; text-only active selection; canonical
ready/partial/stale/authoritative-empty restart; atomic invalid/cross-Account/
duplicate/count/time/malformed refusal with stable diagnostics; and exact/no-
false-snapshot reference-port behavior.

The complete local implementation gate also passes: all 140 target tests in 32
suites, target environment isolation, generated app/MCP contracts, macOS and
generic iOS Simulator staging builds, conversion/capability/query/residual
controls, M0 and clean diff formatting. The synchronized ledger remains at 769
recorded / 754 discovered surfaces, 343 mapped / 164 residual / 43 blockers.
M1 and M2 retain exactly their expected 2 and 164 blockers.

Exact implementation commit `519b4338c7cbe8cc63a01820116bef5283a8625a`
passed immutable GitHub Actions run `33632364285`: conversion traceability
passed in 10 seconds and the isolated target environment passed in 2 minutes
38 seconds with all 140 tests in 32 suites, graph/generated-contract checks,
macOS and generic iOS Simulator staging builds and clean tracked artifacts. All
five obligations pass, and both claimed target surfaces are `verified`.

## Permanent Limits

This ready plan cannot:

- read, seed, persist, display or authoritatively synchronize a suggestion;
- authorize a reader or writer or resolve O-026;
- create, rename, merge, archive, reactivate or reorder suggestion data;
- create canonical Vendor identity or rewrite an Item, Expense or Transaction
  source snapshot;
- decide fixed/excluded picker options, free-text form UX or default values;
- define a Postgres table, handler, grant, RLS policy, Sync Stream or durable
  local store;
- wire a current/target app control, MCP resource/tool, transport or catalog;
- transform, backfill or reconcile a Firebase vendor-default document; or
- authorize hosted resources, deployment, production migration, release or
  cutover.

No production read or mutation, shipped-app implementation, provider
connection, hosted resource, migration, deployment or cutover occurred.
