# EVID-CONTROL-001 — Conversion Control-Plane Bootstrap

- Timestamp: 2026-08-31T16:35:54-07:00
- Surface: `FILE-208B7E9D7F47`
- Class: implementation
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree dirty before this work
- Environment: local repository only
- Source export: not applicable
- Target environment/migration version: not applicable; manifest schema v1
- Operator: Codex

## Commands and Results

| Command | Expected | Result |
|---|---|---|
| `node --check scripts/supabase-conversion-ledger.mjs` | Script parses | pass |
| `node scripts/supabase-conversion-ledger.mjs sync` | Discovery merges and report generates | pass |
| `node scripts/supabase-conversion-ledger.mjs check` | Zero structural errors/warnings | pass |
| `node scripts/supabase-conversion-ledger.mjs report` | Coverage regenerates | pass |
| `node scripts/supabase-conversion-ledger.mjs gate M0` | Nonzero while inventory is unclassified | pass; gate correctly blocked |
| `node scripts/supabase-conversion-ledger.mjs gate M2` | Nonzero while prerequisite milestones are incomplete | pass; cumulative gate correctly blocked |

The synchronized inventory contained 679 recorded surfaces: 667 automatic and
12 manual cross-cutting surfaces. No source surface was missing and validation
reported zero structural errors and zero warnings.

## Scope and Limitations

This is deterministic local evidence for the control tooling only. It does not
prove that source behavior has been characterized, that the initial discovery
rules are semantically exhaustive, or that any Supabase/PowerSync application
surface, migration, security policy, offline path, or cutover operation works.
Those claims remain blocked by the applicable manifest milestones.

## Classification-Batch Extension Verification

On 2026-08-31 the control tool was extended at source hash
`89fd8aa91dbf8f70689b3ebd42a3a5ee1aedadd7d4e436b0bbc4b8bad49e8474`
to apply bounded `classification-batches/*.json` inputs. The implementation
enforces:

- unknown or multiply classified surface IDs become structural errors;
- characterized automatic surfaces require an acknowledged source hash;
- the first reviewed batch application acknowledges the observed hash;
- later source changes are not silently re-acknowledged;
- unsynchronized classification files make `check` fail; and
- four backend batches synchronized with zero errors or warnings while M0/M1
  continued to fail for their real remaining blockers.

## Explicit Re-Acknowledgment Extension

Later on 2026-08-31 the control tool advanced to source hash
`ac766582778c01244b51ec24fa9ad9a6694e7588b513b563fb8be2a7a8d2f39d`.
A deliberate change to an already characterized automatic surface now requires
`acknowledgeSourceHash` in exactly one reviewed classification batch. The tool
accepts it only when it equals the newly observed hash. An intentional
wrong-hash test failed with the requested and observed hashes identified; after
restoring the reviewed hash, sync/check/report returned zero errors and
warnings. This supplies an auditable re-acknowledgment path without weakening
the original no-silent-drift rule.

## Separate Target Migration-Control Discovery

On 2026-09-01 the control tool advanced to source hash
`5028736af14eeb48db09867498da41d386eee1a2f510b82340393079505223f5`.
Automatic Swift discovery now includes
`LedgeriOS/LedgerTargetMigrationCore` and its test directory as separate
platform/test surfaces while retaining the existing application/core scopes.
The reviewed exact-hash acknowledgment, syntax check, synchronization, full
conversion check and report pass at 725 recorded / 710 currently discovered
surfaces with zero errors and the same three documented retired-path warnings.
This is inventory coverage only: it does not link the module into an app,
execute migration behavior or grant provider, production or cutover authority.
