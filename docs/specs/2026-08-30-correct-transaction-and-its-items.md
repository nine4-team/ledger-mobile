# Correct Transaction and Its Items

## Status

Implemented in the Ledger MCP; iOS UI exposure is deferred.

Date: 2026-08-30

## Purpose

Ledger needs one explicit correction operation for cases where a transaction and
all of its currently attached items were recorded in the wrong project or in the
wrong project/inventory scope.

The operation is named:

```text
correct_transaction_and_its_items
```

The name is intentionally about a transaction rather than a Purchase. Purchase is
only one eligible transaction type, and Purchase-specific metadata must not define
the general correction primitive.

This is a data correction. It does not represent goods changing hands, money
moving, a sale, or a return.

## Supported Directions

The operation supports these scope corrections:

- Project A to Business Inventory
- Business Inventory to Project A
- Project A to Project B

A same-project category correction may use the same whole-aggregate machinery for
ordinary mutable transactions. Generated inventory-movement category changes keep
their dedicated rules and trusted operation.

## Whole-Aggregate Contract

The transaction is the aggregate root. A successful correction changes the
transaction and every item currently attached to it in one atomic commit.

The operation must:

- preserve `transaction.itemIds`;
- preserve each item's `transactionId`;
- set the transaction and every attached item to the same resulting `projectId`;
- set the transaction and every attached item to the same resulting
  `budgetCategoryId` when the destination is a project;
- clear `budgetCategoryId` from the transaction and every attached item when the
  destination is Business Inventory;
- detach item spaces that do not belong to the resulting scope;
- return a receipt containing every detached item/space assignment;
- write correction lineage for each affected item; and
- either commit every write or commit nothing.

The operation must not:

- clear item/transaction associations;
- create a Sale, Return, Purchase-from-Inventory, or other financial movement;
- alter amounts, tax, discounts, dates, source, or item status merely because
  the scope changed; valid item prices are preserved, while a project
  destination still enforces the global project-price-at-least-purchase-price
  invariant;
- infer a future project destination for inventory; or
- partially correct a selected subset of the transaction's active items.

## Inputs

The public operation accepts:

| Field | Requirement | Meaning |
| --- | --- | --- |
| `transactionId` | Required | Transaction aggregate to correct |
| `destinationProjectId` | Required, nullable | Destination project; `null` means Business Inventory |
| `destinationBudgetCategoryId` | Conditionally required | Required for a project destination and prohibited for Business Inventory |
| `destinationPurchaseHandling` | Conditionally required, nullable | For an inventory Purchase moving into a project, explicitly choose `project_reimbursement` or `null` for an ordinary project Purchase |
| `dryRun` | Optional; defaults to `true` | Return the complete plan and blockers without writing |
| `requestId` | Optional | Idempotency/audit identifier when supported by the caller |

Destination intent is not part of this operation. If inventory is later planned
for a project, the existing inventory-intent operation records that as a separate,
explicit action.

## Destination Rules

### Destination: Business Inventory

The resulting transaction and items use:

```text
projectId = null
budgetCategoryId = null
```

For an eligible Purchase:

- set `purchaseHandling = inventory_resale` when Purchase handling applies;
- block rather than infer business ownership when `purchasedBy` explicitly names
  a non-business payer;
- clear project-reimbursement state;
- clear `intendedProjectId` and `intendedBudgetCategoryId`; and
- do not infer the former project/category as future destination intent.

Non-Purchase transactions do not receive Purchase-only metadata.

### Destination: Project

The destination category is required. It must be an active, non-system,
canonically itemized category already enabled in the destination project.

The transaction and every attached item receive the destination project and
category. Inventory-only intent fields are cleared.

Purchase-specific handling must be deterministic from an existing explicit state
or an explicit correction choice. The operation must not infer reimbursement from
`purchasedBy` alone. Existing specialized project-reimbursement correction behavior
may route through the shared implementation after supplying its explicit Purchase
handling decision.

### Destination: Another Project

The destination category is required and validated using the same project-category
rules. Incompatible spaces are detached. Explicit Purchase handling and
reimbursement state remain unchanged unless the caller is using a separately
defined Purchase-handling correction.

## Active Membership Validation

Before writing, the operation must resolve active membership from both directions:

1. `transaction.itemIds`
2. all items whose `transactionId` equals the transaction ID

The two ID sets must match exactly. Every active item must also agree with the
transaction's current project and, when project-scoped, its category.

Any missing item, extra reverse-linked item, duplicate ID, scope mismatch, or
category mismatch blocks the operation without writes. Membership repair is a
separate correction and must not be guessed during a scope correction.

## Eligibility and Safety Boundaries

The operation is allowed only for an ordinary, mutable transaction whose complete
active item aggregate can be safely rewritten as a correction.

It must block when any of these conditions apply:

- the transaction is a generated per-batch inventory movement, including a Sale,
  Return-to-Inventory, Sale-to-Inventory, or Purchase-from-Inventory with frozen
  structural identity;
- the transaction is canceled;
- active membership is inconsistent;
- an active item is not in the transaction's current scope/category;
- the transaction or affected items have downstream sale/return movement lineage
  that makes the scope rewrite historical rather than corrective;
- the transaction is used as inventory-entry provenance;
- an invoice, invoice line, active settlement, or payment references the
  transaction or affected item source in a way that would rewrite billing history;
- a destination project/category is missing or invalid;
- the correction would violate item/transaction/category or space invariants; or
- the required atomic writes exceed Firestore's transaction/batch limit.

The operation fails closed. Ambiguous legacy records require a separate reviewed
repair rather than best-effort mutation.

## Space Handling

A non-null `item.spaceId` must belong to the item's resulting project/inventory
scope.

For this whole-transaction correction, incompatible spaces are detached
automatically in the same atomic commit. Dry-run and execution receipts list:

- item ID;
- previous space ID;
- previous space project/inventory scope; and
- whether the referenced space still exists.

The receipt can be used to restore or translate assignments deliberately after the
correction.

## Audit and Lineage

Each affected item receives a `movementKind: "correction"` lineage edge containing:

- item ID;
- transaction ID as both the before and after transaction association;
- source and destination project IDs;
- actor/source;
- request ID when available;
- a note identifying the whole-transaction correction; and
- timestamp.

The transaction should also receive the normal `updatedAt`/`updatedBy` audit
fields. The implementation may add one structured aggregate audit event, but it
must not replace the per-item lineage required for item history.

## Dry-Run Contract

`dryRun: true` is the default. It returns:

- transaction ID and type;
- current and resulting project/category;
- complete active item IDs and count;
- transaction/item field changes;
- Purchase-only metadata changes, if applicable;
- detached space assignments;
- lineage writes;
- calculated atomic write count;
- eligibility result; and
- every blocker with actionable guidance.

Execution must recompute and revalidate the plan. A prior dry-run is informative,
not authorization to apply a stale plan.

## Relationship to Existing Operations

- `update_transaction` remains unchanged and is not expanded into this workflow.
- Individual and bulk item corrections remain available for item-only repairs.
- Sell and Return remain the only operations for real business movements.
- Generated inventory-movement corrections retain their immutability and dedicated
  correction/cancel-and-reissue rules.
- `correct_inventory_purchase_to_project_reimbursement` may remain as a compatible
  specialized entry point, but should delegate to the shared aggregate correction
  implementation after applying its explicit reimbursement semantics.

## Implementation Shape

Use one shared planner/validator and one atomic writer. Public tools or future iOS
actions must call this shared implementation rather than duplicating scope-correction
logic.

The first implementation should be additive:

- add `correct_transaction_and_its_items`;
- do not change existing generic transaction mutation behavior;
- do not change Sell/Return writers or inventory-movement immutability;
- do not broaden Firestore client permissions; and
- expose the operation to iOS later through the same trusted contract if a UI action
  is added.

## Required Verification

Coverage must include:

- project to Business Inventory success;
- Business Inventory to project success;
- project to project success;
- association and `itemIds` preservation;
- category clearing and assignment;
- Purchase-only metadata behavior;
- no inferred inventory destination intent;
- dry-run with zero writes;
- incompatible-space detachment receipts;
- stale or asymmetric membership rejection;
- generated inventory-movement rejection;
- downstream lineage/provenance rejection;
- invoice and settlement rejection;
- invalid destination category rejection;
- atomic-limit rejection rather than partial writes; and
- injected write failure proving all-or-nothing behavior.

Build verification and a disposable production-Firebase smoke test should follow
the repository's normal MCP validation policy. Firebase emulator testing is only
for a focused legacy integration test when explicitly needed.

## Implementation Verification

Implemented and verified on 2026-08-30:

- the TypeScript MCP build passes;
- twelve focused Firestore integration tests cover all supported directions and
  the primary safety blockers;
- the existing generic transaction-to-inventory correction regression passes;
- a disposable production-Firestore smoke verified dry-run isolation, aggregate
  membership preservation, project-to-inventory correction, category clearing,
  space detachment, Purchase metadata cleanup, and per-item correction lineage;
  and
- every disposable production fixture was removed and cleanup was verified.
