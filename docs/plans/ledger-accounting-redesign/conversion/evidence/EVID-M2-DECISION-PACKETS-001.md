# EVID-M2-DECISION-PACKETS-001 — High-Impact Residual Decision Packets

- Timestamp: 2026-09-04 O-042/O-043 amendment
- Class: target mapping design / product-decision preparation
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  from the history now carried by `firebase`; the historical audit began from a
  dirty source checkout
- Production reads or mutations: none
- Target implementation/deployment/migration changes: none
- Product decisions approved by this evidence: none
- Operator: Codex

## Result

The deterministic 184-surface M2 residual is grouped under 47 exact blockers.
Twenty-one reviewable packets now cover all 39 product blockers in the generated
residual queue plus O-042/O-043, which were discovered while reviewing the
already target-mapped Client-rename provider draft:

| Packet | Decisions | Unique surfaces in packet cluster |
|---|---|---:|
| Item accounting and provenance | O-007/O-015 | 49 |
| Transaction posting and lifecycle | O-029/O-032 | 36 |
| Attachment reference and retention | O-023 | 22 |
| Shared reference-data authorization | O-026 | 19 |
| Item tax and acquisition basis | O-031 | 16 |
| Invoice adjustments and sent revisions | O-009/O-034 | 20 |
| Client credit and zero-Invoice model | O-003/O-004/O-005/O-010 | 26 |
| Receipt-line treatment and rounding | O-008/O-030 | 19 |
| Expense locks and collection payment | O-006/O-033 | 14 |
| Client Summary and shared evidence | O-035/O-036 | 11 |
| Space archive and Item assignment | O-037 | 9 |
| Transfer edge policy | O-002/O-011–O-014 | 6 |
| Item capture and acquisition readiness | O-016/O-017/O-027 | 11 |
| Proto migration and authority cutover | O-018/O-019/O-020/O-022 | 5 |
| Project and Client lifecycle | O-024/O-025 | 7 |
| Vendor adjustment and credit balance | O-028 | 2 |
| Inventory destination planning | O-038 | 5 |
| Project-note text validation | O-039 | 8 |
| Project budget pinning | O-040 | 18 |
| Vendor-spend report semantics | O-041 | 2 |
| Client rename and display-name boundary | O-042/O-043 | 0 residual; 9 target-mapped draft surfaces |

Because surfaces can depend on multiple decisions, these clusters overlap.
Together they touch all 177 residual surfaces that have any product-decision
blocker. The other seven surfaces depend only on architecture/spike, physical-
target verification, or canonical-production-evidence blockers. This means a
proposal is available for every product blocker; it does **not** mean those
surfaces are mapped, unblocked, approved, or implementation-ready.

O-021 is explicitly UI-only and does not appear as a mapping-changing blocker in
the generated residual queue. It is intentionally deferred to UX testing rather
than represented as a schema/domain packet.

## Packet Standard

Each packet contains:

- the exact decision and mutually exclusive options;
- confirmed constraints that cannot be silently reopened;
- a recommended outcome with domain/schema/command/query consequences;
- RLS, Sync, offline, concurrency, migration and reconciliation requirements;
- semantic/security/failure/migration acceptance tests; and
- an approval checklist and explicit remaining blockers.

The [packet control README](../../decision-packets/README.md) defines the
authority boundary and closure workflow. The canonical specs and decision log
remain product authority. A packet recommendation does not update a surface to
`target_mapped`.

## Reproduction

The source counts come from:

```bash
npm run conversion:residuals:check
```

The generated register validates every blocker against the product/architecture
authority and lists every exact affected surface. Packet links are recorded in
the decision log and product-to-architecture traceability rows.

A structural audit of the first nineteen packet files verified each contains the
decision requested, confirmed constraints, mutually exclusive options,
conceptual target ownership, authorization/Sync treatment, migration/
reconciliation, acceptance tests, approval consequences, and checklist. The
twentieth O-041 packet and twenty-first O-042/O-043 packet follow the same
required shape. O-042/O-043 were created after independent review rejected a
Client-rename READY attempt; their recommendations approve nothing.

## Guardrails Preserved

- A-003/A-004 remain proposed until the isolated vertical spike passes.
- A-015 and A-016 remain gated.
- No Supabase/PowerSync production implementation, DDL, deploy, migration,
  release, or cutover was performed.
- No production Firebase access or mutation occurred.
- No Firebase adapter or Firebase v2 accounting implementation was introduced.
