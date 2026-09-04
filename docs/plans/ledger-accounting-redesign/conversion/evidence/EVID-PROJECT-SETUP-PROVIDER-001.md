# EVID-PROJECT-SETUP-PROVIDER-001 — Project Setup Supabase/PowerSync Slice

- Timestamp: 2026-09-04
- Class: local implementation evidence / Project setup provider slice
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the Firebase worktree and released app remain unchanged
- Target branch: `codex/supabase-powersync-implementation`
- Slice dossier:
  `conversion/implementation-slices/project-setup-supabase-powersync-vertical-slice.json`
- Verification state: local implementation and immutable exact-commit CI passed;
  connected Auth/PowerSync rehearsal pending
- Implementation commit: `e57b874d4c75f7f833f77221df794cafa0c0d72c`
- Immutable Actions run: `33894323498`

## Outcome

The isolated target now implements the first local Project setup path on top of
the provider-free Project contracts. With no network, the app can accept one
Project using an existing Client or one preallocated new Client, persist the
entire optimistic aggregate in encrypted PowerSync storage, and enqueue one
canonical `project-create-v1` command. The same ordinary-name command can be
applied through a trusted Supabase Postgres handler from Swift or the gated
target MCP tool. O-043 still gates the new-Client name-submission boundary; it
does not affect the existing-Client branch.

The server transaction creates the optional Client, Project, complete selected
category allocation set and immutable operation result together. Exact replay
returns the same result; changed replay cannot rebind the Operation ID. Direct
table mutation is denied, and local database/API tests cover Account,
capability, category-visibility and cross-tenant boundaries.

## Implemented Surfaces

- spike-prefixed local Project, category and allocation schema, indexes, grants,
  RLS and the trusted Project command function;
- synthetic owner/restricted/cross-Account/category fixtures;
- 22 Project pgTAP assertions and local Data API apply/replay/security checks;
- local-only pending Client, Project and allocation overlays plus one insert-only
  upload command;
- Client/Project FIFO command dispatch with exact local operation/overlay and
  terminal-result validation;
- authoritative Project/Client readback that removes the complete linked local
  optimistic aggregate, preventing stale resurrection after later eviction;
- a scoped-user Swift Supabase RPC adapter preserving `Int64` Money and nullable
  allocation/description fields;
- seven Project PowerSync tests and five target MCP Project tests with one shared
  Swift/TypeScript canonical envelope fingerprint;
- Project/category/allocation Sync Stream definitions; and
- an isolated local staging form for new/existing Client Project creation.

## Local Verification

The following evidence passed against disposable local resources:

- `npx --yes supabase@2.116.0 db reset --local --yes`;
- `npm run target:supabase:test:db` — 41 total pgTAP assertions across Client and
  Project suites;
- `npm run target:supabase:test:rpc` — Client and Project local REST/RLS checks;
- `swift test --package-path LedgeriOS --filter LedgerPowerSyncVerticalSliceTests`
  — nine Client provider tests;
- `swift test --package-path LedgeriOS --filter ProjectPowerSyncVerticalSliceTests`
  — seven Project provider tests;
- `npm --prefix LedgerTargetMCP test` — ten target MCP tests;
- `npm --prefix LedgerTargetMCP run check`;
- `npm run target:contracts:check`; and
- database lint;
- all 332 Swift package tests in 67 suites; and
- the isolated macOS and generic iOS Simulator staging target builds.

The complete conversion gates pass after the durable tracker is synchronized.
Exact implementation commit `e57b874d4c75f7f833f77221df794cafa0c0d72c`
passed immutable Actions run `33894323498`, including all three conversion,
target-environment and local-Supabase jobs. This still does not satisfy the
physical hosted vertical-spike gate.

## Review Corrections

The first independent SQL/PowerSync reviews found and the parent independently
corrected:

- a missing authenticated execute grant on the private Project handler;
- a nullable Client-selection discriminator that could bypass branch checks;
- missing Project/budget-management capability initialization and category
  financial-visibility enforcement;
- Project/new-Client identity race windows that could escape durable rejection;
- identifier byte-limit and deterministic category-order mismatches (not final
  Client display-name scalar/byte parity, which remains open under O-043);
- missing Project SQL, REST, offline, transport and cross-runtime tests;
- an upload connector that initially recognized only Client commands;
- missing exact local operation/overlay linkage validation; and
- successful overlays that were not removed after authoritative readback.

## Explicit Open Gates

- O-043 gates only the new-Client branch. Swift, MCP and PostgreSQL currently
  disagree on some Client-name whitespace/control/NUL/size cases, and stored/read
  evidence is not yet distinct from the new-submission converter. The existing
  ordinary-name fixture proves command transport parity, not final validation
  parity or durable rejection for every invalid name.
- A-003/A-004 remain proposed. No hosted Supabase or PowerSync environment has
  been provisioned, and no real Auth/Sync Stream upload/readback has passed.
- O-026 remains open. The spike tests a deliberately stricter capability and
  financial-visibility policy, but does not declare that policy to be approved
  product behavior.
- Permanent authorization loss for an already queued offline command still
  needs a connected-phase terminal-resolution contract so the queue cannot
  retry forever without weakening authorization.
- Stable entity IDs are globally unique opaque identifiers in the target tables,
  while relationships, reads and authorization remain Account-scoped. This must
  stay explicit through migration collision analysis.
- Project hero media remains a separate durability slice.

No Firebase implementation, source data, hosted target resource, production
credential, migration, deployment, release or cutover was changed or used.
