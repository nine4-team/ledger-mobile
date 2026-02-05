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

