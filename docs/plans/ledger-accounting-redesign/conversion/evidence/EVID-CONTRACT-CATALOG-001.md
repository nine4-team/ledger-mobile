# EVID-CONTRACT-CATALOG-001 — Versioned Target Contract Catalog

- Timestamp: 2026-09-01
- Class: implementation / app-MCP contract / operational control
- Repository implementation commit:
  `c79484a8483b1203a4e5c1a95d2b92371e2722aa` on
  `codex/supabase-powersync-implementation`
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree, app project, and current MCP runtime were not
  modified
- Target environment: dependency-free local target package and isolated
  target-only TypeScript compiler package
- Catalog SHA-256:
  `1a42004b2c5b8c322cb092374df6e5fc2f1c89fb506f95c6bb32612fe78e806f`
- Production reads or mutations: none
- Hosted Supabase/PowerSync resources created or contacted: none
- Operator: Codex

## Surfaces

- `CONFIG-B2A2BF619303` — canonical reviewed catalog
- `FILE-3920BDE7C604` — deterministic generator, validator, and negative
  registration controls
- `SWIFT-5FA3004D3855` — generated Swift projection
- `SWIFT-6AA27A022A10` — typed Swift catalog and fail-closed runtime validator
- `TEST-C8A63111BD2B` — Swift parity and boundary suite
- `MCPMOD-CE84DA4C8EA4` — generated TypeScript projection
- `CONFIG-E8C1EA5B72F9` — bounded MCP catalog resource projection
- `CONFIG-5209F00EB920`, `CONFIG-1BF5CA7701CD`, and
  `CONFIG-A02A8D8114A1` — isolated target TypeScript package, exact compiler
  lock, and strict no-emit configuration

## Implemented Contract

One canonical JSON registry now deterministically produces Swift, TypeScript,
and bounded MCP resource projections. The catalog contains only already
implemented target platform capabilities: environment validation, operation
status, sync health, capability discovery, and contract discovery. It contains
no product command, provider SDK, database relation, credential, hosted
resource, or deployment endpoint.

Every advertised capability and contract records an exact version,
availability, authorization policy, telemetry class, executable test owner,
result contract, and stable error set. The generator validates exact shapes,
unique IDs and enum values, cross-references, repository-bounded test owners,
contract versions, reciprocal deprecation projections, a 64-KiB limit, and
provider/persistence/credential/private-payload exclusions. Generated files
embed the same canonical hash and freshness checks reject manual or stale
projection edits.

The generator's check mode executes nineteen intentional malformed-catalog
controls covering duplicate IDs/values; missing security, error, result,
telemetry, test-owner, and version metadata; unknown references; unsupported
versions; invalid or divergent deprecations; and provider, persistence,
credential, and private-payload leakage. Each mutation must fail for its
expected reason before valid projection freshness is accepted.

The current Firebase MCP package and files remain source evidence only. The ten
broader source-MCP replacement surfaces remain `target_mapped`: they are not
advanced by this foundation because full product contracts, transport runtime,
container/deployment controls, and app/MCP execution parity do not exist yet.

The checkpoint also corrected two conversion controls exposed by the first
implemented/verified target surfaces: the residual generator now treats every
status at or above `target_mapped` as mapped rather than misclassifying later
states as blockerless residuals, and the Firestore query extractor excludes
target-only check/generation scripts from its Firebase-source candidate count.
Parent-commit Actions run `33557226244` independently passed the complete
isolated-target job but failed conversion traceability because those two derived
controls were stale. That run is recorded as diagnostic evidence only, not as a
passing catalog gate; this checkpoint regenerates both artifacts and requires a
new exact-commit run.

## Reproduction

```bash
npm --prefix LedgerTargetMCP ci --ignore-scripts
node --check scripts/generate-target-contracts.mjs
npm run target:contracts:check
npm run target:environment:check
swift test --package-path LedgeriOS
npm run target:project:generate
npm run target:staging:build:macos
npm run target:staging:build:ios
node scripts/supabase-conversion-ledger.mjs sync
node scripts/supabase-conversion-ledger.mjs report
node scripts/supabase-conversion-ledger.mjs check
git diff -- LedgeriOS/LedgeriOS.xcodeproj/project.pbxproj
git diff --check
```

Local results on 2026-09-01:

- clean isolated TypeScript install: pass; two audited packages, zero
  vulnerabilities, and no lifecycle scripts;
- canonical generation/freshness/hash parity: pass;
- nineteen negative registration controls: pass;
- strict TypeScript 5.9.3 no-emit compilation: pass;
- six generated-catalog Swift tests: pass;
- 29 total target-package tests across three suites: pass;
- target environment/source-contamination guard: pass;
- target staging macOS and generic iOS Simulator builds: pass;
- source `LedgeriOS.xcodeproj` diff: empty;
- tracked diff formatting check: pass; and
- conversion ledger: 711 recorded surfaces, 696 currently discovered, zero
  errors, and three explained retired-path warnings.
- immutable GitHub Actions run
  `https://github.com/nine4-team/ledger-mobile/actions/runs/33559241558` for
  exact commit `c79484a8`: pass; and
- both `Conversion state and traceability` and `Isolated target environment`
  jobs passed, including clean generated-artifact checks, isolated dependency
  install, contract validation/negative controls, all target tests, macOS
  build, generic iOS Simulator build, and clean tracked diff.

## Verification Status

- `CONTRACT-CATALOG-TEST-001`: passed locally. Generated Swift loads from the
  canonical bytes/hash and exactly matches the runtime operation/readiness
  enum registries and implemented platform contract set.
- `CONTRACT-CATALOG-TEST-002`: passed locally. Canonical JSON, Swift,
  TypeScript, and MCP resource projections have exact hash and entry parity;
  strict compilation and stale-output checks pass.
- `CONTRACT-CATALOG-TEST-003`: passed. The local negative-control suite and
  immutable exact-commit pull-request run both pass, including the clean-diff
  guard that rejects rewritten generated artifacts.

## Explicit Limits

This evidence does not implement or prove:

- any product/accounting command, query, DTO, handler, or user-facing flow;
- the eventual complete replacement of the current MCP product catalog;
- an MCP transport server, Principal/Account resolution, container, runtime
  health, deployment, or app-versus-MCP command execution parity;
- Supabase Auth, Postgres, Data API grants, RLS, Storage, Edge Functions, or
  PowerSync Sync Streams;
- physical offline behavior, hosted staging, provider selection, or the
  A-003/A-004 spike; or
- migration, production release, cutover, or production authority.
