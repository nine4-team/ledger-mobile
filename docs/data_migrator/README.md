# Data migrator (legacy Supabase export → Firestore bundle)

This folder contains a CLI migrator that transforms a legacy Supabase export into a
Firestore-ready JSON bundle that matches the mobile app data contracts.

## Usage

```bash
node docs/data_migrator/migrate-ledger-export.mjs \
  docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-2026-02-04T20_45_23.037Z.json \
  --storage docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-storage-2026-02-04T20_45_23.037Z \
  --check-storage
```

Optional flags:

- `--out <dir>`: output directory (default: `docs/data_migrator/out/v1`)
- `--storage <dir>`: storage export directory for media
- `--check-storage`: verify files exist in the storage export
- `--version <version>`: migration version label (default: `v1`)
- `--canonicalize-budget-category-ids`: emit budget categories with slug-based IDs (instead of legacy UUIDs)

## Output

The migrator writes three files into the output directory:

- `bundle.json`: Firestore bundle (doc path + data)
- `report.json`: counts + warnings
- `media-manifest.json`: list of media files to upload later

### `bundle.json` shape

```json
{
  "meta": {
    "migrationVersion": "v1",
    "generatedAt": "2026-02-04T20:45:23.037Z",
    "sourceExport": "ledger-server-export-....json",
    "accountId": "..."
  },
  "documents": [
    {
      "path": "accounts/<accountId>/items/<itemId>",
      "data": { "id": "<itemId>", "...": "..." }
    }
  ],
  "counts": {
    "accounts/<accountId>/items": 785
  }
}
```

### Media handling

Media attachments are converted to `AttachmentRef` objects with:

- `url: "offline://<mediaId>"`
- `kind: "image" | "pdf"`

The `media-manifest.json` file maps each `mediaId` to the legacy Supabase URL
and the local storage-export path (if provided). This can be used by a separate
upload script to move files into Firebase Storage and then update the Firestore
docs with the final URLs.

## Seed the Firestore emulator

The bundle is a list of Firestore document paths + data. Use the seed script
to load it into the emulator:

```bash
# 1) Start emulators from repo root
firebase emulators:start

# 2) Install Firebase admin deps (one-time)
cd firebase/functions
npm install
cd ../..

# 3) Seed Firestore from the bundle
node firebase/functions/scripts/seed-firestore-emulator.mjs \
  docs/data_migrator/out/v1/bundle.json \
  --project demo-ledger
```

Notes:
- If you already set `FIRESTORE_EMULATOR_HOST`, the script will use it.
- Re-running the script overwrites the same docs (idempotent).

## Notes

- Transaction references are resolved against **both** legacy row IDs and
  legacy domain IDs. Missing references become `null` (never placeholders).
- Amounts are parsed into integer cents using half-away-from-zero rounding.
- Empty strings on optional fields are normalized to `null`.
- Budget category IDs are **kept as legacy UUIDs by default** so all legacy references continue to work.
  If you need stable cross-export IDs, pass `--canonicalize-budget-category-ids` to emit slug-based IDs
  (e.g. `furnishings`, `design-fee`). The legacy UUID is always preserved at
  `budgetCategories/<id>.metadata.legacy.sourceCategoryId`.
# Data migrator workspace

This folder is a scratchpad for working with legacy Supabase exports (DB + Storage) and producing migration reports / import-ready outputs for the mobile app.

## What you have here

- `ledger-server-export-*-*.json`: database export (tables + rows).
- `ledger-server-export-*-storage-*/`: storage export (bucket objects like item images and receipts).
- `validation-report.json`: older validation output.
- `validation-report.v2.json`: current validation output produced by the script below.

## Validate an export

Generate a validation report (checks basic foreign key-style relationships).

```bash
node docs/data_migrator/validate-ledger-export.mjs \
  docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-2026-02-04T20_45_23.037Z.json \
  --out docs/data_migrator/validation-report.v2.json
```

Optionally sample-check that referenced media URLs exist in a storage export directory:

```bash
node docs/data_migrator/validate-ledger-export.mjs \
  docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-2026-02-04T20_45_23.037Z.json \
  --storage docs/data_migrator/ledger-server-export-1dd4fd75-8eea-4f7a-98e7-bf45b987ae94-storage-2026-02-04T20_45_23.037Z \
  --check-storage \
  --out docs/data_migrator/validation-report.v2.storage.json
```

