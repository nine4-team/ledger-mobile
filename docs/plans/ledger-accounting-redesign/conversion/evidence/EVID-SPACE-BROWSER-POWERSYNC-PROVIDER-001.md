# EVID-SPACE-BROWSER-POWERSYNC-PROVIDER-001 — Offline Space Browser Provider READY Boundary

- Timestamp: 2026-09-06
- Class: DRAFT-to-READY design evidence; no executable implementation or hosted rehearsal
- Reviewed base: `2297e8dbe7f7f0febb7e33b4da0be591d4c82ade`
- Target branch: `codex/supabase-powersync-implementation`
- Slice: `space-browser-powersync-provider`

## Bounded Outcome

The slice implements the frozen provider-free active Space list through the
existing encrypted target database, an exact Account plus Project-or-Business-
Inventory `space_browser` Sync Stream subscription, the Account runtime, and an
isolated list-to-existing-detail staging flow.

The browser may reuse existing Space/core-details/checklist relations and their
validated hierarchy, but it owns separate browser completeness. Completion of
the active assignment-destination stream, generic database connectivity or row
presence cannot establish browser readiness or authoritative empty.

## Security and Offline Boundary

Every represented row and completion event remains bound to the signed
Principal, active Account membership and exact immutable scope. Foreign,
mixed-scope, duplicate, malformed or incomplete local evidence fails closed
without revealing hidden rows or counts. Restart may retain valid cached rows
but resets current-process subscription completion. Replacement, cancellation,
membership loss and workspace close unsubscribe and join all observers before
the encrypted database closes.

## Explicit Deferrals and READY Blockers

The implementation does not add search, numeric Item counts, card media,
archived-list UI, archive effects, Space/Item/checklist mutation, MCP, hosted
authentication or Sync proof, source migration, Firebase work, production
routing, release or cutover. Unknown Item count is never rendered as zero.
A-003 and A-004 remain proposed until the separately defined hosted spike gate
passes. The physical provider also remains DRAFT because
`space-core-details-powersync-provider`,
`space-assignment-destination-powersync-picker`, and
`account-workspace-runtime-isolation` are implemented but not verified. The
vertical-slice method requires verified dependencies before READY, so this
dossier is not part of the active implementation checkpoint.

## Frozen Implementation Boundary

The exact comment scaffolds, existing dependency files, stream/schema/runtime,
staging composition, package/project generation and static-check touchpoints are
enumerated with SHA-256 hashes and permitted changes in the slice dossier.
Independent READY review must find no unresolved P0-P3 issue before promotion;
implementation then requires independent executable review, the complete local
batch gate and one exact immutable CI run.
