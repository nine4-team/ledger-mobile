# EVID-M2-SPIKE-PROTOCOL-001 — Executable Vertical-Spike Protocol

- Timestamp: 2026-08-31
- Class: architecture/spike preparation
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Staging resources provisioned or used: none
- Supabase/PowerSync implementation, DDL or deployment: none
- Architecture decisions approved by this evidence: none
- Operator: Codex

## Result

The broad vertical-spike criteria are now an executable, resumable
[protocol](../../vertical-spike-protocol.md) with:

- an explicit no-production/no-Firebase-adapter safety boundary;
- a disposable thin vertical slice that exercises real Swift→local SQLite→
  PowerSync→trusted handler→Postgres→authorized sync behavior without becoming
  target DDL authority;
- synthetic `tiny`, reported-scale 7,000-Item baseline, and 20,000-Item headroom
  fixtures with separate generated-media testing;
- scored Supabase Auth versus temporary Firebase Auth and three-way complex-
  optimism comparisons;
- named S0–S9 phases and sixteen mandatory hard-failure test IDs;
- exact physical-device, seven-day offline, logout/pending-work, revocation,
  poison-queue, Item-history, media, schema-evolution, backup/restore, performance
  and cost evidence requirements;
- machine-readable run/artifact layout and a no-go default; and
- an exact update sequence for architecture decisions, residual mappings,
  conversion gates and execution state after a run.

## Blocker Coverage

| Blocker | Protocol output |
|---|---|
| A-003 | Postgres invariants, locks, RLS/query plans, latency, backup/restore and reconciliation evidence |
| A-004 | PowerSync local/sync durability, readiness, footprint, byte/cost and schema-evolution evidence |
| A-007 | Disqualifying security tests plus weighted launch-identity comparison and retirement plan |
| A-015 | Identical fault/concurrency fixtures across overlay, tagged-row and hybrid candidates |
| A-016 | Measured offline lease/unlock/revocation/logout behavior; still requires product/security approval |
| Physical target verification | Required physical iPhone/macOS matrix; Simulator alone cannot pass |

The protocol does not close these blockers. It defines the evidence that may
close them after an authorized, isolated run.

## Current Reference Check

The official PowerSync Swift, data-encryption, validation-error, and RLS/Sync
Stream references and Supabase Auth/Firebase third-party Auth references were
rechecked on 2026-08-31. The protocol requires them, actual provider versions,
and pricing to be rechecked and pinned again in every run manifest because those
interfaces and commercial terms can change.

## Remaining Preconditions

- product-owner approval of hosted-resource budget and cleanup ownership;
- isolated staging resources and staging-only identities/credentials;
- staging bundle/configuration with compiled production-resource refusal;
- an approved supported-device matrix and thresholds recorded before final
  measurement; and
- implementation of disposable spike harness/fixtures only after explicit
  authorization.

## Guardrails Preserved

- A-003/A-004 remain proposed.
- A-007/A-015 remain unresolved until comparative evidence is reviewed.
- A-016 remains blocked on product/security approval even after technical tests.
- No product packet recommendation became authority.
- No production Firebase/Supabase/PowerSync access occurred.
- No Firebase adapter, Firebase v2 implementation, target DDL, deployment,
  migration, release or cutover was created or performed.
