# EVID-TELEMETRY-001 — Privacy-Safe Telemetry and Correlation

- Timestamp: 2026-09-01
- Class: implementation / observability contract / privacy control
- Repository baseline: `ca7e062d` on
  `codex/supabase-powersync-implementation`; implementation is in the current
  bounded diff pending its exact commit
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current application are not modified
- Claimed target surfaces: `SWIFT-C1EC0E1D9BE6`, `TEST-BDC6ADC6F366`
- Slice dossier:
  `conversion/implementation-slices/privacy-safe-telemetry-and-correlation.json`

## Ready-Gate Scope

The ready dossier traces the platform capability outcome and exact architecture
headings into a bounded target-only contract for:

- stable registered event, metric, dimension, telemetry-class and unit values;
- environment/build/contract scope derived from validated target configuration;
- typed, one-way, domain-separated correlations with no raw identifiers in an
  emittable value;
- exact allowlisted dimensions/correlations and bounded measurements/envelopes;
- canonical offline encoding and reconstruction; and
- deterministic sensitive-data redaction versus identifier/unclassified-data
  refusal.

The comment-only scaffolds and complete dossier passed the ready gate before
behavioral implementation began. The slice has no unresolved product,
architecture, credential, spend, provider or production blocker.

## Implemented Contract

`LedgerTargetCore/PrivacySafeTelemetry.swift` now provides:

- closed target-owned event, metric, dimension-key, unit and correlation-kind
  registries;
- event/metric definitions that must resolve a telemetry class from the
  generated versioned contract catalog;
- `TelemetryBuildScope`, derived only from a `ValidatedLedgerEnvironment`, with
  safe app/build/source/contract version validation and no endpoint/resource
  values;
- a non-serializable 256-bit correlation key and typed session, Principal,
  Account, operation, entity and Sync-checkpoint HMAC-SHA256 derivation with
  build/environment/kind domain separation;
- emittable correlations that encode only kind and 64-character digest, never
  the typed source identity or key;
- exact per-signal dimension values, correlation kinds, metric unit/ranges,
  deterministic sorting, canonical millisecond JSON, and a 1,536-byte ceiling;
- catalog-mediated decoding that revalidates telemetry class, scope, field
  allowlists, bounds and canonical size rather than treating decoded bytes as
  trusted; and
- a closed redaction policy where only allowlisted dimensions and opaque
  correlations include, protected classes return stable redaction codes, and
  raw identifiers/unclassified material return stable refusal codes without
  carrying a source value.

There is deliberately no recording protocol, sink, SDK, buffer, destination,
network/file I/O, app/MCP/handler call site, product event or production switch.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter PrivacySafeTelemetryTests`:
  pass, four tests;
- `swift test --package-path LedgeriOS`: pass, 43 tests across seven suites;
- `npm run target:environment:check`: pass;
- `npm run target:contracts:check`: pass, including strict target TypeScript;
- `npm run target:project:generate`: pass;
- `npm run target:staging:build:macos`: pass;
- `npm run target:staging:build:ios`: pass for generic iOS Simulator;
- source `LedgeriOS.xcodeproj` diff from `fe018501`: empty; and
- tracked diff formatting check: pass.

## Verification Status

- `TELEMETRY-TEST-001`: passed locally. Registration, generated-class
  resolution, exact unit/range/dimension/correlation rules and bounded canonical
  construction are deterministic and fail closed.
- `TELEMETRY-TEST-002`: passed locally. Canonical event/metric bytes reconstruct
  offline; reordered fields normalize; same-scope correlation is stable while
  environment/build/key/kind changes separate it; encoded bytes contain none of
  the source fixture identities.
- `TELEMETRY-TEST-003`: passed locally. Protected classes redact, raw identifiers
  and unclassified material refuse, and duplicate/disallowed/mismatched/invalid/
  oversized candidates produce stable failures without a partial envelope.
- `TELEMETRY-TEST-004`: exact-commit pull-request CI is pending, so the slice
  remains `implemented`, not `verified`.

## Explicit Limits

This evidence does not create or authorize a telemetry SDK, sink, destination,
file/network buffer, Account/Principal lookup, Auth, Supabase/PowerSync resource,
app/MCP/handler emission, product event, dashboard, alert, retention policy,
production data access, migration, deployment, release, or cutover. Current
`NavLifecycleLog` and MCP telemetry surfaces remain only `target_mapped`; shared
contract proof will not advance them.
