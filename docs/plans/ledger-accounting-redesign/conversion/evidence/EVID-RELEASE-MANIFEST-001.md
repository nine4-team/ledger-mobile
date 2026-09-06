# EVID-RELEASE-MANIFEST-001 — Reproducible Release Manifest and Artifact Integrity

- Timestamp: 2026-09-01
- Class: implementation / release evidence / artifact integrity
- Exact implementation commit:
  `81726e3bf7345f06fcc6a38cb826142387d39b47` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree, current application and release scripts are
  not modified
- Claimed target surfaces: `SWIFT-B2CF26BDA1A8`, `TEST-E323BA653B17`
- Slice dossier:
  `conversion/implementation-slices/reproducible-release-manifest-and-artifact-integrity.json`

## Ready-Gate Scope

The ready dossier traces the platform capability outcome and exact architecture
headings into a bounded target-only contract for:

- validated environment/profile/channel and repository/app/build identity;
- exact generated catalog plus schema/query/operation/Sync versions;
- closed artifact/platform/dependency-lock identities with positive byte counts
  and SHA-256 evidence;
- deterministic sorting, canonical bytes and one manifest content digest;
- pure byte tamper verification and exact required evidence coverage;
- explicit compatibility validation; and
- a permanently evidence-only disposition that cannot represent release,
  deployment, feature authority or cutover approval.

The two comment-only scaffolds and complete dossier passed the ready gate before
behavioral implementation began. The slice has no unresolved product,
architecture, credential, spend, provider or production blocker.

## Implemented Contract

`LedgerTargetCore/LedgerReleaseManifest.swift` now provides:

- closed release channel, platform, artifact-kind, dependency-ecosystem and
  evidence-only authority values;
- bounded application version, 40/64-character lowercase source revision,
  stable public artifact/lock IDs and exact SHA-256 values;
- a build identity derived from `ValidatedLedgerEnvironment` that binds the
  profile, positive build number, source revision, exact schema/query/operation/
  Sync versions and generated contract-catalog hash without carrying resource
  identifiers or provider values;
- pure artifact and dependency-lock evidence factories and byte verifiers with
  separate size and hash failures and no filesystem/provider access;
- compatibility policies with environment-bound channel allowlists, exact
  artifact/lock requirements, duplicate rejection and fixed count ceilings;
- deterministic artifact/lock sorting, canonical millisecond JSON, a content
  digest over the manifest content, a 4,096-byte ceiling and catalog-mediated
  offline decode/revalidation; and
- exact environment/profile/channel/contract/catalog/evidence/tamper failures
  plus a single `evidenceOnly` disposition that grants no release authority.

There is deliberately no signing key, signer, notarizer, SBOM generator,
filesystem reader, archive builder, provider SDK, upload, deployment, migration
runner, feature activation, operator approval or production switch.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter LedgerReleaseManifestTests`:
  pass, four tests;
- `swift test --package-path LedgeriOS`: pass, 47 tests across eight suites;
- `npm run target:environment:check`: pass;
- `npm run target:contracts:check`: pass, including strict target TypeScript;
- `npm run target:project:generate`: pass;
- `npm run target:staging:build:macos`: pass;
- `npm run target:staging:build:ios`: pass for generic iOS Simulator;
- source `LedgeriOS.xcodeproj` diff from `fe018501`: empty; and
- tracked diff formatting check: pass.

Immutable GitHub Actions run
[`33567370249`](https://github.com/nine4-team/ledger-mobile/actions/runs/33567370249)
passed on that exact implementation commit. Its `Conversion state and
traceability` and `Isolated target environment` jobs both passed, including
conversion coverage and generated-artifact cleanliness, target dependency and
environment boundaries, generated app/MCP contracts, the complete 47-test
target package suite, the macOS build, the generic iOS Simulator build and the
final clean-diff guard.

## Verification Status

- `RELEASE-MANIFEST-TEST-001`: passed locally. Closed values, validated build
  scope, exact evidence coverage, sorted canonical content and evidence-only
  disposition are deterministic.
- `RELEASE-MANIFEST-TEST-002`: passed locally. Reordered drafts normalize to
  identical bytes/digests, decode and revalidate offline, and pure byte
  verification detects changed size/content.
- `RELEASE-MANIFEST-TEST-003`: passed locally. Environment/profile/channel,
  contracts/catalog, duplicate/missing evidence, invalid values, digest tamper,
  noncanonical encoding and oversized candidates fail closed; encoded fixtures
  contain no paths, URLs, credentials, provider or user identities.
- `RELEASE-MANIFEST-TEST-004`: passed in immutable GitHub Actions run
  `33567370249` on exact implementation commit `81726e3b`, including all 47
  target tests and both target builds.

All four obligations pass, so the slice and its two target-only surfaces are
`verified`. Current release scripts remain only `target_mapped`.

## Explicit Limits

This evidence does not create or authorize signing/notarization keys, a signer,
SBOM generator, filesystem reader, app archive, DMG/appcast, TestFlight/App Store
or Sparkle adapter, upload, deployment, hosted resource, migration/reconciliation
run, feature activation, production release, operator approval or cutover.
Current release scripts remain only `target_mapped`; shared-contract proof will
not advance them.
