# EVID-M2-WHOLE-MANIFEST-001 — Whole-Manifest Target-Mapping Audit

- Timestamp: 2026-09-03 correction
- Class: target mapping design / coverage control
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  from the history now carried by `firebase`; the historical audit began from a
  dirty source checkout
- Production reads or mutations: none
- Target implementation/deployment/migration changes: none
- Operator: Codex
- Method: `target-mapping-method.md`

## Result

Across the 17 batches containing target-relevant surfaces, within the current
18-batch manifest of 686 recorded surfaces:

- 427 surfaces have `replace`, `redesign`, or `migrate` dispositions;
- 250 are exactly `target_mapped`;
- 177 remain characterized/blocked with at least one explicit mapping-changing
  decision, spike or production-evidence blocker;
- zero mapped surfaces are missing owner, target surface, security, Sync,
  migration rule, reconciliation, tests or acceptance fields; and
- zero remaining target-relevant surfaces have an empty blocker list.

This is not an M2 pass: the deterministic M2 gate correctly remains blocked by
177 surfaces. It is proof that the residual is explicit rather than forgotten
or represented by generic “implement target” placeholders.

The residual is also published as deterministic machine-readable and reviewable
artifacts:

- `conversion/residual-decision-register.generated.json`; and
- `conversion/residual-decision-register.generated.md`.

`npm run conversion:residuals:check` regenerates the expected artifact in
memory, verifies that every blocker resolves to the product traceability or
architecture decision authority, and fails on drift or an unknown blocker.

## Coverage by Completed Mapping Evidence

| Evidence | Mapped | Held |
|---|---:|---:|
| App shell/presentation | 39 | 0 |
| Identity/session | 8 | 0 |
| Media/attachments | 15 | 4 |
| Platform/control | 38 | 3 |
| Clients/Projects/reference | 29 | 23 |
| Item creation/Link | 14 | 17 |
| Inventory/Transactions/provenance | 23 | 43 |
| Invoicing/collection/budget | 19 | 25 |
| Spaces/review | 16 | 11 |
| Reporting/search/export | 19 | 18 |
| Backend/Auth/Functions/rules/Storage/query | 30 | 32 |
| Cutover control | 0 | 1 |
| **Total** | **250** | **177** |

The largest residual dependencies are O-015 (46 surfaces), O-007 (31), O-032
(23), O-023 (22), O-005 and O-029 (20 each), O-026 (19), O-031 (16), and
O-009/O-034 (15 each), and O-040 (17 target-relevant surfaces; 18 affected
surfaces overall). A surface may depend on multiple
decisions, so blocker frequencies do not sum to 177.

## Gate Interpretation

- M0 passes: every source surface is classified.
- M1 remains blocked by exactly `MAN-DATA-001` and `MAN-CUTOVER-001`.
- M2 remains blocked by 177 explicit residual surfaces in the original audit
  population; the expanded live ledger reports the current count separately.
- A-003/A-004 remain proposed until the isolated vertical spike passes.
- This mapping audit is not production migration authorization and creates no
  Firebase adapter or Firebase v2 implementation.

## Reproduction

```bash
npm run conversion:residuals:check
npm run conversion:check
npm run conversion:gate:m0
npm run conversion:gate:m1  # expected to fail on two evidence blockers
npm run conversion:gate:m2  # expected to fail on the current residual
```
