# EVID-PRODUCT-AUTHORITY-001 — Product Authority to Surface Cross-Reference

- Timestamp: 2026-09-01
- Class: product-behavior / conversion-coverage control
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/deployment/migration changes: none
- Operator: Codex

## Result

All 686 conversion surfaces resolve through their one reviewed classification
batch to an explicit authority set in `product-authority-crosswalk.json`:

- 573 surfaces are in product-governed batches;
- 113 are platform, query/profiling, cutover, residual, or conversion-control
  surfaces governed by technical authorities;
- all 427 target-relevant surfaces resolve to one of those reviewed scopes; and
- all five canonical target specs are explicitly present and distinguished from
  current-product and historical-evidence documents.

The five target specs are:

1. `docs/specs/invoice-centered-project-accounting.md`;
2. `docs/specs/inventory-item-invoicing-lifecycle.md`;
3. `docs/specs/proto-item-capture.md`;
4. `docs/specs/client-identity-and-project-transfers.md`; and
5. `docs/plans/non-item-receipt-lines/design.md`.

The conversion check now fails when a classification batch has no authority
entry, a referenced authority file disappears, a product batch lacks a
canonical target spec, a canonical target spec is unused, a surface cannot
resolve through its batch, or either generated audit artifact is stale.

## Authority Semantics

- `canonical_target` plus confirmed decision-log entries define redesigned
  product behavior.
- `current_product` records shipped outcomes or constraints that require an
  explicit preserve/correct/improve/redesign/retire decision.
- `historical_evidence` can inform migration and regression fixtures but cannot
  authorize a target writer or schema.
- `architecture_authority` and `conversion_control` own technical obligations
  and execution safety, never unresolved product policy.

This is reviewed batch-level authority traceability, not a claim that every
source file corresponds one-to-one with one spec paragraph. Exact requirement,
command/schema, and test ownership remains in the capability dossiers,
decision traceability, manifest target maps, and later implementation evidence.

## Artifacts

- `conversion/product-authority-crosswalk.json` — reviewed source mapping;
- `conversion/product-authority-audit.generated.json` — stable surface IDs,
  batch ownership, authority roles, and counts; and
- `conversion/product-authority-audit.generated.md` — human-readable audit.

## Reproduction

```bash
node --check scripts/supabase-conversion-ledger.mjs
npm run conversion:sync
npm run conversion:check
npm run conversion:report
npm run conversion:gate:m0
```

Result: 686 recorded surfaces, 674 currently discovered, zero errors and zero
warnings; M0 passes. No Firebase application behavior, Supabase/PowerSync
schema, deployment, production data, or cutover state was changed.
