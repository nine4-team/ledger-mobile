# Prompt Pack — Chat D: Document lineage semantics (association vs intent edges)

You are a “naive but capable” AI dev. Your job is to **update the spec docs only** (no app-code changes) so the Firebase mobile migration specs clearly document the lineage system we are using.

This is correctness-critical; do not invent new behavior. Treat the below as the source-of-truth background and map it into the specs.

## Goal
Document the finalized LineageEdge semantics for Firebase mobile:

- We maintain **append-only lineage edges** in Firestore at:
  - `accounts/{accountId}/lineageEdges/{edgeId}`
- We use lineage edges for two different needs:
  1) **Association audit edges** (always): what *actually happened* to item↔transaction linkage over time.
  2) **Intent edges** (sometimes): why it happened (Sold/Returned/Correction).

Association edges are **not** mutually exclusive with intent edges.

## Why this approach (short rationale)
We want:
- A complete audit trail (including mistakes/corrections) without relying on inference.
- UI that can cleanly show “Sold” and “Returned” sections without pollution from normal linking/unlinking.
- Canonical inventory flows (allocate/deallocate/sell) to remain the single place where “Sold” intent is written (server-owned request-doc invariants).

## Definitions (copy into specs as definitions)
### `movementKind = "association"` (audit; always)
Written **for every change** to `item.transactionId` (including to/from `null`):
- `fromTransactionId = old item.transactionId`
- `toTransactionId = new item.transactionId`
- `source = "server"`

This is the durable “what happened” record.

### `movementKind = "sold"` (intent; deterministic)
Written by the canonical inventory flows (server-owned request-doc handlers) when the user performs an economic inventory operation:
- project → business inventory (canonical deallocation/sale)
- business inventory → project (allocation purchase mechanics)
- project → project (sell item to another project)

These are the same “inventory ops” family; they should all label the move as `sold`.

### `movementKind = "returned"` (intent; deterministic)
Written when an item becomes linked to a Return transaction (destination transaction is “Return”).
This can be implemented server-side (because the destination transaction type is known there).

### `movementKind = "correction"` (intent; explicit only)
Written only when the system has explicit “fix mistake” intent (e.g., UI action labeled as correction).
Do **not** infer correction purely from an association change; that becomes guessy.

### `source`
Use provenance to distinguish where edges come from:
- `source = "server"`: Cloud Functions / request-doc handlers / triggers
- `source = "app"`: direct client intent edges (if/when used)
- `source = "migration"`: backfills (if any)

## Concrete Firebase implementation facts (for parity evidence / “observed in code” notes)
These facts are to be referenced in the spec as “observed in code” pointers:

- Canonical inventory request-doc handlers append lineage edges in:
  - `ledger_mobile/firebase/functions/src/index.ts`
    - `handleProjectToBusiness` → writes `movementKind: "sold"`
    - `handleBusinessToProject` → writes `movementKind: "sold"`
    - `handleProjectToProject` → writes `movementKind: "sold"`
- Association edges are appended for every `item.transactionId` change by a server trigger in:
  - `ledger_mobile/firebase/functions/src/index.ts`
    - `onItemTransactionIdChanged` → writes `movementKind: "association"`
    - also writes `movementKind: "returned"` when destination transaction type is Return
- This design is documented (and must stay documented) in a comment block at the top of:
  - `ledger_mobile/firebase/functions/src/index.ts`

## Files to update (spec-only)
Update these docs so a reader can understand the above without reading code:

1) `20_data/data_contracts.md`
   - Ensure `LineageEdge` includes:
     - `movementKind?: "sold" | "returned" | "correction" | "association" | null`
     - `source?: "app" | "server" | "migration"`
     - (optional scope hints) `fromProjectId?: string | null`, `toProjectId?: string | null`
   - Add short explanation that association edges are audit and may co-exist with intent edges.

2) `40_features/inventory-operations-and-lineage/feature_spec.md`
   - In the “Lineage (required)” section, document:
     - association vs intent edges
     - sold written by canonical request-doc flows
     - returned when linking into Return transaction
     - correction is explicit only

3) `40_features/inventory-operations-and-lineage/flows/lineage_edges_and_pointers.md`
   - Expand “Behavior contract” to say:
     - Always append association edges on transactionId change (server-side trigger)
     - Canonical ops append sold intent edges (in the same server-owned transaction)
     - Return linking appends returned intent edges (in addition to association)
     - Correction edges are explicit only (not inferred)

4) `40_features/project-transactions/ui/screens/TransactionDetail.md`
   - Ensure this screen contract uses intent edges for UI sections:
     - “Sold” = edges `movementKind == "sold"` (NOT association)
     - “Returned” = edges `movementKind == "returned"`
   - Mention that association edges exist for audit but are not rendered as Sold/Returned.

## Output requirements
- Do not change behavior. This task is docs-only.
- Keep language simple (avoid jargon). Use short definitions and a small rationale.
- Add “Observed in code” pointers using full paths (above) so future devs know where to look.
- If you find contradictory text in these docs (e.g., claiming mutual exclusivity), update it to match this contract.

