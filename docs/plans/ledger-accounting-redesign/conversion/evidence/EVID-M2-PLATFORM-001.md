# EVID-M2-PLATFORM-001 — Platform, Transport, Release, and Control Target Mapping

- Timestamp: 2026-08-31
- Class: target mapping design evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/deployment/release/migration changes: none
- Operator: Codex
- Mapping batch: `M0-PLATFORM-CONTROL-001`
- Method: `target-mapping-method.md`

## Scope and Result

The platform/control batch contains 41 `replace`, `redesign`, or `migrate`
surfaces. Thirty-eight now have complete target maps. Three remain deliberately
`characterized` because named decisions or physical evidence can still change
their exact target contract.

The completed map covers environment/build projection, app composition, MCP
deployment and request security, generated versioned contracts, stable errors,
capability publication, Account workspace context, notes versus immutable audit
evidence, protected artifact export, readiness, telemetry, hosting/links,
TestFlight/Sparkle artifacts, staged rollout and target test infrastructure.

## Mapping Decisions

- `LedgerEnvironmentManifest` and validation are the sole environment authority.
  Startup refuses mixed Auth/data/Sync/Storage/MCP/telemetry/local-state
  resources before opening infrastructure. Secrets are not manifest data.
- `TargetAppCompositionRoot` constructs one `AppDependencies` graph from
  backend-neutral ports. The redesigned runtime contains no Firebase adapter,
  provider switch, generic string-path repository or duplicated listener/write
  authority.
- MCP stdio/HTTP transports resolve every request to a verified Principal,
  active Account membership and registered capability. There is no static actor,
  built-in production ID or environment Account fallback.
- One generated or parity-tested `VersionedContractCatalog` owns command/query
  schemas, enums, errors, capabilities, authorization policies, versions and
  deprecations for app and MCP. It does not publish persistence DTOs/raw schema.
- Release and hosting map to immutable environment/contract-aware manifests,
  signed/hash-verified artifacts, stable provider-independent product links,
  staging-first promotion, canary/rollback records and post-release observation.
- Observability maps to redacted correlation envelopes and health that separates
  local DB, required-stream readiness, queue, replication, attachments, Auth and
  server state. Protected exports use bounded artifact leases and receipts.
- Target tests use semantic fixtures and isolated synthetic identities rather
  than Firebase-shaped factories or production defaults.

Architecture guidance now explicitly defines manifest validation, contract
catalog publication and protected artifact export ports. The running Firebase
app remains unchanged and its tooling/configuration stays source-only.

## Withheld Surfaces

- `CONFIG-2F4D7DBFD096`: exact Swift SDK/lock graph awaits the A-003/A-004
  Supabase/PowerSync vertical spike.
- `MAN-OFFLINE-001`: exact optimistic projection and offline authorization/readiness
  contract awaits A-015, A-016 and physical target verification.
- `MCPMOD-4B5868CBF5DC`: exact Item price/tax basis calculation awaits O-008 and
  O-031; legacy helper behavior is not provisional authority.

These holds retain exact blockers instead of hiding implementation choices in a
generic “platform” abstraction.

## Verification

The batch must contain 41 target-relevant surfaces, 38 `target_mapped` entries
and the three named holds. Every mapped entry must have non-empty owner, target
surfaces, security, Sync, migration rule, reconciliation, tests and acceptance
fields. Conversion/capability/query checks and M0 remain required. M1 remains
blocked only by the canonical production profile and O-022 cutover evidence.

This evidence proves reviewed target mapping only. It does not approve A-003 or
A-004, select A-007, implement platform code or infrastructure, access
production, deploy MCP/hosting, build/release an app, migrate data, or cut over.
