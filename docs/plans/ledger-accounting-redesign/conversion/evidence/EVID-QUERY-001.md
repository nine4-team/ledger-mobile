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
- `query-contract.generated.json` — 170 Firestore-candidate files inspected, 74
  files with recognized operations, and 386 source occurrences at source digest
  `87a3c1deb568f3e5a5bd35dc316dff38eccaf4fb83e8ecc02c61c77887150da4`
- `query-contract.generated.md` — compact generated coverage report
- `scripts/extract-firestore-query-contract.mjs` — deterministic generator/checker

The generated JSON SHA-256 is
`2a43de6e59844d081237c8d9731846662e0862190823ea854c2238256b0a6a14`.
The generated Markdown SHA-256 is
`970b84d56837b78958d78003122ec86398e0ccd1928160b14c746fd6eb27ea41`.

These totals and hashes are the values in the original committed artifact at
`3e1d435b` and in the current artifact. Earlier text saying 169 candidates and
recording different generated hashes was stale evidence prose, not a change to
the artifact or its source digest.

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
