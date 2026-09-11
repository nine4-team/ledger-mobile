# EVID-SLICE-METHOD-001 — Enforceable Vertical-Slice Implementation Method

- Timestamp: 2026-09-01
- Class: implementation-process / coverage control
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/deployment/migration changes: none
- Operator: Codex

## Result

The redesign now has one required implementation protocol rather than a set of
related prose recommendations:

- `vertical-slice-implementation-method.md` defines authority precedence,
  slice boundaries, exact requirement anchors, contract mapping, verification,
  lifecycle gates, change control, evidence and reviewer stop conditions;
- `implementation-slices/_template.json` defines the machine-readable dossier
  shape and is ignored until copied to a real slice ID;
- `implementation-slice-audit.generated.json` and `.md` report current slice and
  target-surface coverage; and
- `scripts/supabase-conversion-ledger.mjs` validates slice dossiers and their
  relationship to manifest statuses.

The validator requires, at the appropriate lifecycle gate:

- exact existing Markdown authority paths and section headings;
- authority roles allowed by the claimed surfaces' reviewed product-authority
  crosswalk;
- observable invariants, confirmed decision IDs and reciprocal verification
  coverage;
- every contract category populated or explicitly not applicable;
- test kinds derived from actual Postgres, handler, Data API grant, RLS, Sync,
  offline, media, app/MCP, migration, reconciliation and operational scope;
- no blockers at `ready` or later;
- implementation evidence at `implemented` or later;
- passing evidence for every verification at `verified` or later;
- rehearsal evidence at `rehearsed` or later; and
- bidirectional status consistency between each slice and its claimed manifest
  surfaces.

No target-relevant surface is currently `implemented` or later, and no slice
has begun. The initial audit therefore correctly reports zero slices, zero
claimed surfaces and 427 unclaimed target-relevant surfaces. Unclaimed
`target_mapped` surfaces are allowed until a bounded slice starts; advancing any
one of them to `implemented` without exactly one corresponding slice fails.

## Negative Controls

Validation first accepted a temporary fully traced `ready` technical-control
slice with an exact architecture heading, one claimed mapped surface, complete
contract applicability decisions and reciprocal requirement/test coverage.

It was then exercised against deliberately invalid temporary state and was
required to fail for:

- a `ready` slice without exact requirements/contracts/verifications; and
- an implemented target surface without a correspondingly advanced slice.

The temporary probes were removed before final verification.

## Reproduction

```bash
node --check scripts/supabase-conversion-ledger.mjs
npm run conversion:sync
npm run conversion:check
npm run conversion:report
npm run conversion:gate:m0
```

This evidence proves the process control only. It does not claim any Ledger
product slice, Supabase schema, RLS policy, PowerSync stream, target migration,
deployment or production cutover exists.
