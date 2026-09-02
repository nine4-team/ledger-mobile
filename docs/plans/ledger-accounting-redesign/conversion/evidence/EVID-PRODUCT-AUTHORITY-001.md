# EVID-PRODUCT-AUTHORITY-001 — Product Authority to Surface Cross-Reference

- Timestamp: 2026-09-02
- Class: product-behavior / conversion-coverage control
- Original evidence commit: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`;
  its historical branch label was `dev`
- Current source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6`
  on `firebase`; target work remains isolated on
  `codex/supabase-powersync-implementation`
- Production reads or mutations: none
- This authority-registry correction changes no executable target behavior,
  deployment, migration, hosted resource or production state
- Operator: Codex

## Result

All 777 conversion surfaces resolve through their one reviewed classification
batch to an explicit authority set in `product-authority-crosswalk.json`:

- 623 surfaces are in product-governed batches;
- 154 are platform, query/profiling, cutover, residual, or conversion-control
  surfaces governed by technical authorities;
- all 515 target-relevant surfaces resolve to one of those reviewed scopes; and
- all seven canonical target specs are explicitly present and distinguished from
  current-product and historical-evidence documents.

The seven target specs are:

1. `docs/specs/invoice-centered-project-accounting.md`;
2. `docs/specs/inventory-item-invoicing-lifecycle.md`;
3. `docs/specs/proto-item-capture.md`;
4. `docs/specs/client-identity-and-project-transfers.md`;
5. `docs/specs/projects.md`;
6. `docs/specs/spaces.md`; and
7. `docs/plans/non-item-receipt-lines/design.md`.

The sixth entry corrects authority metadata rather than choosing new behavior:
`spaces.md` already declared itself a target-state spec and already stated the
corrected typed Space/template/checklist rules. The 2026-09-02 Space-template
dependency audit found that it was still labeled `current_product`. It is now
canonical for both the Spaces/review and Project/Client/reference batches, so a
later slice cannot preserve the source hard-delete, checked-state-copy or no-op
template defects as target behavior.

The seventh-spec audit made the analogous correction for `projects.md`. That
document already separates an explicit Target Redesign Requirements section
from the Firebase mechanics retained below it as current/migration evidence.
The Project-details dependency audit made the preserved optional-description
rule explicit there and registers the spec as canonical for the Project/Client/
reference batch. This formalizes the reviewed preserve/correct split: optional
description remains, while generic field dictionaries, free-text Client
identity, partial edits and orphaning delete do not become target behavior.

The direct Space-creation dependency audit also registers architecture documents
02, 04, and 07 for the reviewed Spaces/review batch. They trace the shared
operation lifecycle, narrow port, and migration separation used by that slice;
they do not change `spaces.md` product authority or resolve any open product
decision.

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

Result: 777 recorded surfaces, 762 currently discovered, zero errors and three
explained retained-path warnings; M0 passes. No Firebase application behavior,
Supabase/PowerSync schema, deployment, production data, or cutover state was
changed.
