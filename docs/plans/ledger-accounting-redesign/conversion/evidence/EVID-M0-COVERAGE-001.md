# EVID-M0-COVERAGE-001 — Complete Source-Surface Classification and Gap Audit

- Timestamp: 2026-08-31
- Class: deterministic conversion-control and static coverage evidence
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Generated artifact: `conversion-coverage.md`

## Scope and Method

The control plane rediscovered the repository from the filesystem, merged all
automatic and manual cross-cutting surfaces, applied all 18 bounded
classification batches, and validated source presence/hash acknowledgment,
status, disposition, behavior, evidence, and batch ownership. The gap audit then
queried the manifest independently for unclassified surfaces, empty current
behavior, missing evidence, missing batch ownership, and blocked surfaces.

Coverage is not based on a hand-maintained feature checklist alone. Automatic
discovery covers Swift application/services/models/state/views/components/
logic/platform/tests, Firestore rule matches, Cloud Functions and modules, MCP
modules/tools/resources, Firebase migration/audit/configuration, existing test
evidence, and build/release configuration. Twelve manual surfaces cover behavior
that source-file discovery cannot prove, including production data, Auth,
Storage, offline/local lifecycle, queries/indexes, reports, environments,
hosting, observability, and cutover.

## Result

- 686 total recorded surfaces: 674 currently repository-discovered plus 12
  manual cross-cutting surfaces;
- 680 characterized, four verified control/tool surfaces, and two explicitly
  blocked surfaces;
- zero unclassified surfaces;
- zero surfaces without current-behavior text;
- zero surfaces without evidence;
- zero surfaces without one classification batch;
- zero missing-source, source-drift, structural, or validation warnings; and
- `M0 PASS: Inventory classified`.

Approved dispositions are:

| Disposition | Count |
|---|---:|
| Preserve | 135 |
| Redesign | 186 |
| Replace | 239 |
| Retire | 37 |
| Source only | 87 |
| Migrate | 2 |

The final 115-surface batch covered the app shell, Auth/account/member
presentation, reusable components/theme, navigation, Item action/menu/editor
helpers, filtering/grouping, native camera/document/image behavior, pure
calculations, all remaining tests, obsolete placeholders, and the legacy MCP
Sale fixture. The final audit also assigned evidence and batch ownership to the
manual cutover-control surface.

## Commands and Outcomes

```text
jq empty classification-batches/M0-APP-SHELL-PRESENTATION-001.json
npm run conversion:sync
npm run conversion:check
npm run conversion:report
npm run conversion:gate:m0
npm run conversion:capabilities:check
npm run conversion:queries:check
npm run conversion:residuals:check
git diff --check
```

All completed successfully. Deterministic capability and query artifacts were
current. The manifest-specific audit counts above were also zero.

`npm run conversion:gate:m1` correctly remains blocked by exactly two evidence
gates:

1. `MAN-DATA-001` — a selected, hashed, canonical read-only production profile
   or export has not confirmed actual production collections, shapes, counts,
   enums, orphans, Auth, and references; and
2. `MAN-CUTOVER-001` — O-022 has not approved and rehearsed the exact Firebase
   freeze, final-delta, late-writer recovery, and rollback boundary.

Local `firebase-export*` directories are emulator/export artifacts without
sufficient provenance to silently promote one to canonical production evidence.
They remain source fixtures until their origin, target, timestamp, completeness,
and immutable hash are explicitly established.

## Interpretation and Limitations

M0 proves that every currently discoverable repository/manual conversion
surface has a deliberate disposition and evidence owner. It does not prove
runtime feature parity, production data completeness, target schema quality,
security, offline durability, implementation, migration correctness, or cutover
readiness. New files or changed characterized source hashes fail subsequent
checks and reopen the inventory.

This evidence authorizes advancement into bounded target mapping for already
ready capabilities while M1's two blockers remain visible. It does not authorize
Firebase application work, target implementation, production access, migration,
release, or cutover.
