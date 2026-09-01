# EVID-PROTECTED-ARTIFACT-001 — Protected Artifact Export Lifecycle

- Timestamp: 2026-09-01
- Class: implementation / offline contract / protected artifact lifecycle
- Branch: `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and current report/export implementations are
  not modified
- Claimed target surfaces: `SWIFT-7452FE59FE81`, `TEST-1FC8EF92E971`
- Slice dossier:
  `conversion/implementation-slices/protected-artifact-export-lifecycle.json`

## Ready-Gate Scope

The dossier limits this target-only provider-free foundation to:

- an already-authorized immutable snapshot reference carrying exact hash,
  visibility scope, profile version and authority version;
- a policy-bounded request and deterministic request fingerprint;
- a short-lived local lease lifecycle with explicit expiry, handoff outcome,
  cleanup-required state and stable rejection results;
- deterministic offline reconstruction with no path, URL, token, credential,
  provider handle, Account, Principal or entity identity; and
- an evidence-only receipt that cannot prove physical file protection/deletion,
  authorize report contents or authorize delivery to a client.

The slice explicitly leaves O-023 attachment retention and O-036 client-shared
report evidence/delivery untouched. It contains no renderer, filesystem access,
share/print/download adapter, app/MCP wiring, provider SDK, hosted resource,
migration, production action, release or cutover authority.

## Ready-Gate Verification

The two comment-only scaffolds were created before behavior. Their stable
surface IDs are classified in `M0-PLATFORM-CONTROL-001`, claimed by exactly one
slice, and mapped to exact architecture requirements plus domain, offline,
rejection and operational verification obligations.

The machine-enforced `ready` gate passed before behavioral code replaced the
scaffolds.

## Implemented Contract

`LedgerTargetCore/ProtectedArtifactExport.swift` now provides:

- fixed opaque export and snapshot IDs, an opaque visibility-scope digest,
  exact snapshot/output SHA-256 values, bounded profile/authority versions and
  canonical epoch-millisecond values;
- a deterministic policy with sorted content/destination allowlists, positive
  output and lease ceilings, a bounded canonical-evidence size and one policy
  fingerprint;
- an immutable snapshot reference, policy-validated request fingerprint and a
  path-free `ProtectedArtifactLease` carrying only export/fingerprint/expiry/
  byte-ceiling evidence;
- a replay-validated requested → materialized → handoff-recorded → cleanup-
  required → cleaned lifecycle, plus pre-materialization cancellation/failure;
- exact request/output hash binding, monotonic timestamps, pre-expiry
  materialization/handoff, post-expiry cleanup recovery and stable mismatch/
  transition/expiry failures;
- sorted canonical request/lifecycle/receipt bytes, schema and content digests,
  strict noncanonical/tamper/size refusal and offline reconstruction; and
- an evidence-only terminal receipt whose `destinationAccepted` and
  `cleanupRecorded` values are deliberately not proof that a Client received an
  artifact or that a file was physically deleted.

There is no file handle, local path, URL, renderer, byte writer, data-protection
API, share/print/download adapter, recipient, delivery evidence, attachment
reference or retention command.

## Local Verification

Local results on 2026-09-01:

- `swift test --package-path LedgeriOS --filter ProtectedArtifactExportTests`:
  pass, four tests;
- `swift test --package-path LedgeriOS`: pass, 51 tests across nine suites;
- `npm run target:environment:check`: pass;
- `npm run target:contracts:check`: pass, including strict target TypeScript;
- `npm run target:project:generate`: pass with no tracked project rewrite;
- `npm run target:staging:build:macos`: pass;
- `npm run target:staging:build:ios`: pass for generic iOS Simulator;
- conversion, capability, query and regenerated residual controls plus M0 pass;
- source `LedgeriOS.xcodeproj` diff from `fe018501`: empty; and
- tracked diff formatting check: pass.

## Verification Status

- `PROTECTED-ARTIFACT-TEST-001`: passed locally. Closed values, opaque scope,
  exact snapshot/request/output binding, legal lifecycle and evidence-only
  receipt are deterministic.
- `PROTECTED-ARTIFACT-TEST-002`: passed locally. Request, lifecycle and receipt
  evidence reconstruct exactly offline, including cleanup after lease expiry.
- `PROTECTED-ARTIFACT-TEST-003`: passed locally. Unsafe values, disallowed
  formats/intents, policy/fingerprint/hash mismatch, invalid bounds, expiry,
  illegal transitions, noncanonical bytes, digest tamper and oversize fail
  closed with stable results.
- `PROTECTED-ARTIFACT-TEST-004`: planned. The exact implementation commit must
  pass both GitHub Actions jobs before the slice can become `verified`.

The slice and exactly its two target-only surfaces are `implemented`. Current
report, export, PDF/share and platform destination surfaces remain only
`target_mapped`.

## Explicit Limits

This evidence does not show that any artifact bytes were created, protected,
shared, printed, saved, cleaned or deleted. `cleanupRecorded` is evidence from
a future adapter, not physical-deletion proof. `destinationAccepted` is a local
handoff outcome, not proof of recipient delivery. This slice does not approve
any report field, receipt-evidence inclusion, client-delivery mechanism,
attachment retention policy or production operation.
