# EVID-QUERY-001 — Current Firestore Query Contract

- Timestamp: 2026-08-31
- Class: source characterization and deterministic control tooling
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Environment: local source inspection only
- Production reads or mutations: none
- Operator: Codex

## Artifacts

- `current-query-contract.md` — reviewed query families, callers, offline
  expectations, index implications, target mapping rule, and limitations
- `query-contract.generated.json` — 169 Firestore-candidate files inspected, 74
  files with recognized operations, and 386 source occurrences at source digest
  `87a3c1deb568f3e5a5bd35dc316dff38eccaf4fb83e8ecc02c61c77887150da4`
- `query-contract.generated.md` — compact generated coverage report
- `scripts/extract-firestore-query-contract.mjs` — deterministic generator/checker

The generated JSON SHA-256 is
`5036c5b36615527e334acb505fb6b434fc979a62d915b39089cf7813cbb5661e`.
The generated Markdown SHA-256 is
`3b240b83e4b78caf9343dee1072da3ce0724e82401b6b0d29cc957338a4cac2e`.

## Commands and Result

```bash
node --check scripts/extract-firestore-query-contract.mjs
npm run conversion:queries:generate
npm run conversion:queries:check
```

All passed. The catalog contains filters, collection-group queries, ordering,
limits, offsets, cursors, listeners, document/collection/bulk reads,
projections, and aggregates across iOS, MCP, Functions, migration, and audit or
repair tooling.

## Findings

- Current iOS generic repositories rely on cached snapshots, pending local
  writes, and live listeners; MCP and Functions are online-only.
- The only explicit legacy product orderings found are item lineage by
  `createdAt asc` and project notes by `createdAt desc`.
- MCP list endpoints commonly use unordered offset/limit pagination and dynamic
  filter composition. Target behavior needs deliberate stable ordering/cursors.
- The repository declares the lineage composite and users/invites/legacy
  members collection-group indexes, but does not prove deployed console-only
  indexes or every dynamic combination.

## Limitations

This evidence proves reproducible static source coverage, not runtime usage,
production query success, missing-index behavior, deployed index parity, or
historical query paths absent from the repository. Those remain production-read
or deployment-evidence work. No target schema is inferred from query syntax.
