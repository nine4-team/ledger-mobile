# Prompt: build a legacy→mobile data migrator (Supabase export)

You are implementing a **data migrator** in this repo (`ledger_mobile`). The migrator takes a **legacy Supabase export** (DB JSON + exported Storage files) and produces **import-ready data** for the mobile app’s current data model.

## Inputs (already in repo)

- **DB export JSON**: `docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-2026-02-04T20_45_23.037Z.json`
  - Shape: top-level `tables` object with arrays like `public.items`, `public.transactions`, `public.item_lineage_edges`, etc.
- **Storage export dir** (bucket objects): `docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-storage-2026-02-04T20_45_23.037Z/`
  - Contains bucket folders like `item-images/`, `receipt-images/`, `other-images/`, `business-logos/`.

There is also a validator script you can use/extend:

- `docs/data_migrator/validate-ledger-export.mjs`

## Core requirements

- **Repeatable CLI**: implement a command-line tool (Node/TS or Node ESM) that can be run locally and re-run safely.
- **Deterministic IDs**: preserve legacy IDs where the target model allows it; otherwise produce a stable mapping (same input → same output).
- **Relationship preservation**: keep relationships (project↔space↔item↔transaction) wherever possible.
- **No “extra stuff”**:
  - Do **not** add flags/labels like `"incomplete history"`.
  - Do **not** add “migration-only” fields to the target output unless the target model already has a place for them.
  - Only output what the mobile app needs.

## Critical rule: missing transaction references

In this dataset, some rows reference transaction IDs that are not present in `public.transactions`.

When migrating any reference to a transaction ID that cannot be resolved, **set the reference to `null`** (not an empty string, not a sentinel value, not a label).

This applies at minimum to:

- `public.item_lineage_edges.from_transaction_id`
- `public.item_lineage_edges.to_transaction_id` (if missing)
- `public.items.previous_project_transaction_id`
- any other transaction reference fields encountered

## What “resolved” means (important)

Legacy transactions have **two IDs**:

- Row ID: `transactions.id`
- Domain ID: `transactions.transaction_id`

Legacy references (like `items.transaction_id`, lineage edges) may use the **domain ID**.

Resolution rule:

- Treat a transaction reference as resolved if it matches **either** `transactions.transaction_id` **or** `transactions.id`.
- When writing the migrated reference, use whatever ID type the **target model** expects (decide this explicitly and keep it consistent).

## Storage/media handling

The DB export includes media objects with `url`, `fileName`, `mimeType`, etc. The storage export directory contains the actual files.

Implementer should:

- **Keep media lists** in the target output only if the mobile model supports them.
- If the target model expects media to be uploaded elsewhere (e.g. Firebase Storage), provide a separate “upload step” script or an output manifest (paths + metadata) that an upload step can consume.
- Do not invent new URL formats; if you can’t upload during migration, keep what the target model needs (or `null`) and stop there.

## Output: decide + document it

You must identify the mobile app’s current persistence model and write to one of these (choose one, document why):

- **Firestore import JSON** (collections + docs) suitable for bulk import tooling, or
- **SQLite seed** (SQL or JSON fixtures) if the app seeds local DB, or
- **App-level import bundle** (one JSON file that the app can import at runtime)

The output format must be:

- versioned (include a small header with `generatedAt`, source export filename, and migration version),
- deterministic,
- easy to validate (counts per entity).

## Suggested implementation plan (do this, in order)

1. **Inspect target model**
   - Find where “projects / spaces / items / transactions” are defined/consumed in `src/data/`.
   - Identify required fields and any derived fields.
2. **Write a parser layer**
   - Load the export JSON, expose typed accessors for each `public.*` table.
   - Normalize empty strings to `null` for optional reference fields.
3. **Build ID indexes**
   - `itemsByItemId`, `itemsByUuid`
   - `transactionsByRowId`, `transactionsByDomainId`
4. **Transform entities**
   - Map accounts, users, projects, spaces, items, transactions.
   - For any transaction reference: resolve; if not resolved → `null` (no extra flags).
5. **Handle lineage edges**
   - Migrate edges into whatever representation the target model uses.
   - If `from_transaction_id`/`to_transaction_id` can’t be resolved → set to `null`.
6. **Emit output**
   - Write into `docs/data_migrator/out/<timestamp or version>/...`
   - Include a concise report (counts, warnings).
7. **Validation**
   - Reuse/extend `validate-ledger-export.mjs` or create a new validator for the *output* format.
   - Ensure “no dangling refs” in output (except where set to `null` by rule).

## Acceptance checks

- Running the migrator twice on the same input yields the same output (byte-for-byte or functionally identical with stable ordering).
- No new “migration-only” fields/labels were introduced.
- Missing transaction references are `null` in output (not empty string, not “unknown”, not “incomplete history”).
- Storage check (optional) confirms referenced files exist in the storage export directory, or references are omitted/null according to target model needs.

## Deliverables

- A CLI script under `docs/data_migrator/` (or `scripts/`) with usage in a README.
- Output artifacts written under `docs/data_migrator/out/`.
- A short report file next to the output (`report.json`) with entity counts and warnings.

