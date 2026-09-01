# EVID-PROTECTED-ARTIFACT-001 — Protected Artifact Export Lifecycle

- Timestamp: 2026-09-01
- Class: target mapping / ready-gate evidence; implementation pending
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

Implementation and test results will be added only after the machine-enforced
`ready` gate passes. This record currently proves scope and sequencing, not
behavior.

## Explicit Limits

This evidence does not show that any artifact bytes were created, protected,
shared, printed, saved, cleaned or deleted. It does not approve any report
field, receipt-evidence inclusion, client-delivery mechanism, attachment
retention policy or production operation.
