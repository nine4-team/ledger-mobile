# Target Mapping Method

Status: required M2 guidance; M0 complete, M1 evidence-gated

## Purpose

M2 converts each reviewed `replace`, `redesign`, or `migrate` disposition into
an exact Supabase/PowerSync target responsibility without turning the source
file structure into the target architecture. Mapping is recorded on the same
stable manifest surface and in its existing classification batch so one source
surface cannot acquire competing owners during a long run or context handoff.

M2 is design evidence. It does not authorize code, DDL, deployment, production
access, migration, release, or cutover.

## Required Mapping Record

Before a target-relevant surface becomes `target_mapped`, its batch entry must
contain:

| Field | Required meaning |
|---|---|
| `target.owner` | One bounded context or operational owner accountable for the outcome |
| `target.surfaces` | Exact typed command, query/snapshot, port, handler, table/projection family, migration transform, test suite, or operational artifact replacing the source responsibility |
| `target.securityRequirements` | Principal/Account authorization, RLS/Storage/MCP policy, sensitive-field visibility, non-enumeration, or an explicit statement that the pure presentation surface receives only pre-authorized values |
| `target.syncRequirements` | Required local tables/Sync Streams/readiness, durable-operation behavior, media behavior, or an explicit reason the surface is online/operator-only |
| `migration.rule` | Preserve/correlate/transform/quarantine/omit/retire rule for source data or behavior; never “copy as-is” without a named invariant |
| `migration.reconciliation` | Counts, hashes, ID/relationship/amount/media coverage, semantic fixture parity, or an explicit non-data source-only/retirement check |
| `verification.tests` | Named contract, unit, RLS, Sync Stream, offline, fault, migration, reconciliation, UI, or operational tests owned by the target |
| `verification.acceptance` | Observable outcome that distinguishes preserved value from a copied source defect |
| `blockers` | Only decisions/evidence/spikes that can still change the mapping; no generic “target implementation” placeholder |

The mapping references canonical architecture vocabulary. It does not need to
invent a unique port or table for every source file. Several source surfaces may
map to one target command/query/test authority when the dossier proved they are
duplicate mechanics. One source surface may name several target surfaces only
when its current responsibility genuinely crosses those owners.

## Status Rules

- `characterized`: disposition and target-neutral outcome are known, but target
  ownership or a mapping-changing decision remains open.
- `blocked`: current behavior or the target map cannot be completed without the
  named evidence/decision; used sparingly because it also blocks M1.
- `target_mapped`: every required mapping field is concrete. A non-mapping
  implementation dependency may remain, but no open question may change the
  named owner, operation/query boundary, security model, Sync responsibility,
  migration treatment, or acceptance test.
- `implemented`, `verified`, `rehearsed`, and `cutover_ready`: require their own
  later evidence and a correspondingly advanced machine-checked dossier under
  `implementation-slices/`; target-mapping prose never advances them
  automatically.

Do not mark a surface mapped merely because an architecture document mentions
its feature. Conversely, a provider selection may remain open when the complete
backend-neutral contract, authority, security, local-read behavior and adapter
responsibility are already fixed and the provider choice cannot change them.

## Mapping Order

Map dependency foundations before accounting features:

1. environment/composition, operation lifecycle, app shell and identity;
2. encrypted local state, media and Sync readiness;
3. Account/Client/Project/reference data;
4. Item identity, creation and accounting Link;
5. Inventory, provenance, Transactions and corrections;
6. Invoicing, collection and budget authority;
7. Spaces/review and work queues;
8. reporting/search/export/MCP projections; and
9. source export, transform, release, observability, rehearsal and cutover.

Within a batch, map provider-neutral presentation and pure test replacements
alongside the capability they serve. Do not create a generic repository, generic
CRUD command bus, raw database projection, or Firebase adapter to make mapping
appear uniform.

## Review Procedure

For each bounded batch:

1. read the owning dossier, governing product decisions and relevant
   architecture sections;
2. query the manifest for target-relevant surfaces in that batch;
3. map each surface to the smallest exact target authority and acceptance test;
4. leave any mapping-changing decision explicitly characterized with its
   decision ID;
5. synchronize and validate the manifest;
6. query for empty target/migration/verification fields and generic blockers;
7. run M0/M1/M2 gates and record the expected blockers; and
8. update `execution-state.md` with counts and the next exact batch.

M2 is complete only when every target-relevant surface is honestly mapped and
the cumulative M0/M1 prerequisites pass. A percentage or a passing compile is
not a substitute.

Actual implementation follows `vertical-slice-implementation-method.md`. A
surface cannot advance beyond `target_mapped` merely because this mapping is
complete.
