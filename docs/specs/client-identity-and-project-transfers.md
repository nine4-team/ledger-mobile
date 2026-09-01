# Client Identity and Project Transfers
Status: target-state redesign — core direction approved; accounting details noted where open
Last updated: 2026-08-31
Program tracker: [../plans/ledger-accounting-redesign/README.md](../plans/ledger-accounting-redesign/README.md)
Parent accounting model: [invoice-centered-project-accounting.md](invoice-centered-project-accounting.md)
Item lifecycle: [inventory-item-invoicing-lifecycle.md](inventory-item-invoicing-lifecycle.md)

## Purpose

Ledger needs a durable Client identity because one client may own multiple
projects. A free-text client name cannot safely prove that two projects belong
to the same client.

The first feature that requires this identity is a direct project-to-project
Item Transfer. When the same client owns both projects, users may move Items
directly instead of routing them through Business Inventory and manufacturing a
sale, return, or new purchase that did not occur.

## Confirmed Product Direction

1. Target Transaction types are globally limited to exactly `purchase`,
   `return`, and `transfer`.
2. Purchase and Return are scope-relative: Purchase means the scope owner paid;
   Return means the scope owner received money back. The Client owns a project;
   1584 owns Business Inventory.
3. A project `purchase` therefore means the client paid money for goods and/or
   services. An inventory `purchase` means 1584 paid for inventory goods.
4. A project `return` means the client received money back. An inventory
   `return` means 1584 received an inventory vendor refund.
5. A project `transfer` is the single non-cash Transaction exception. It records
   Items being reallocated between two projects owned by the same Client.
   Transfer is invalid in Business Inventory.
6. A Transfer creates one linked record in the source project and one linked
   record in the destination project.
7. The user initiates both records through one bulk Transfer action.
8. The destination picker offers only other active projects whose authoritative
   `clientId` equals the source project's `clientId`.
9. “Bypasses Business Inventory” means the Item changes directly from the source
   `projectId` to the destination `projectId`; it is never temporarily assigned
   `projectId = null` and Ledger creates no inventory purchase or sale.
10. The Transfer itself does not mean the client bought or returned the Item.
    Ledger does not manufacture a new destination Item charge, source client
    credit, Invoice line, payment, or refund solely because the Transfer
    happened.
11. A project owned by a different Client is never an eligible Transfer
   destination. A real ownership change follows the inventory sale/return and
   invoicing rules instead.

## Target Global Transaction Taxonomy

| Type | Global meaning | Project scope | Business Inventory scope |
|---|---|---|---|
| `purchase` | The scope owner paid for goods and/or services | Client paid a vendor or 1584 | 1584 paid an inventory vendor |
| `return` | The scope owner received money back | Client received a vendor or 1584 refund | 1584 received an inventory vendor refund |
| `transfer` | The same Client's Item moved directly between that Client's projects; no cash moved | Two linked project records | Invalid |

The target removes new project writes of `sale`, `paymentToBusiness`, `fee`,
`expense`, and `to inventory`:

- Invoice collection writes `purchase`, because the client paid 1584 for the
  Invoice's goods and/or services.
- A pending Invoice credit is not a `return`; a `return` exists only when the
  client actually receives money back.
- Fees and 1584-paid Expenses are Invoicing source records, not Transaction
  types.
- Inventory sale/return occurrences are hidden Item provenance, not project
  Transaction types.

Legacy values remain read-compatible during migration and must not be rewritten
without an evidence-backed mapping.

## Client Entity

### Storage and identity

Clients are account-scoped:

```text
accounts/{accountId}/clients/{clientId}
```

The minimal Client contract is:

| Field | Requirement | Meaning |
|---|---|---|
| `id` | required | Opaque Client document ID |
| `accountId` | required | Owning Ledger account |
| `name` | required | Current user-facing Client name |
| `isArchived` | required | Hides the Client from new-project selection without deleting history |
| `createdAt` | required | Audit timestamp |
| `updatedAt` | required | Audit timestamp |

Contact people, email, phone, billing addresses, legal name, communication
preferences, and other CRM-like fields may be added later. They are not required
to implement safe Transfers and should not delay the identity migration.

### Project relationship

Every target-state project has a required `clientId` pointing to a Client in the
same account.

`project.clientName` may remain temporarily as a denormalized display and legacy
compatibility field, but it is never identity and never authorizes a Transfer.
New and updated writers derive it from the selected Client while compatibility
readers still need it.

Invoices, reports, and paid history preserve the appropriate Client-name
snapshot for historical display. Renaming a Client updates current project
display without rewriting frozen paid documents.

### Client lifecycle

- Project creation selects an existing Client or creates one, then stores its
  `clientId`.
- Editing the Client's name happens on the Client, not independently on each
  project.
- A Client with projects or accounting history is archived, not hard-deleted.
- Client merge is a separate future correction workflow. Changing project
  `clientId` must not be treated as an ordinary text edit because it changes
  Transfer eligibility and accounting ownership.

## Transfer User Experience

### Entry point

From a project's Items surface, the user may select one or more Items and choose
**Transfer to Another Project**.

The action is available only when:

- every selected Item currently belongs to the source project;
- the source project has a resolved `clientId`;
- at least one other active project has the same `clientId`; and
- no selected Item has a state that the approved transfer rules block.

### Destination picker

The picker:

- excludes the source project;
- excludes Business Inventory;
- excludes archived projects by default;
- excludes every project with a different or missing `clientId`;
- compares immutable IDs, never normalized names; and
- identifies the common Client and both project names in the confirmation UI.

If legacy projects share a `clientName` but lack `clientId`, Ledger must require
Client resolution before Transfer. It must not guess that matching text means
matching ownership.

### Confirmation

The confirmation shows:

- source project;
- destination project;
- Client;
- selected Items;
- any source live-Invoice changes;
- the source and destination budget effect once the amount rule is finalized;
  and
- any Item that cannot be transferred, with a reason.

One confirmation creates both records and moves all accepted Items. The batch is
all-or-nothing; partial success is not permitted.

## Paired Transfer Records

One logical Transfer has a stable operation/correlation ID and two Transaction
documents:

- **source record** — `type = transfer`, source role, attached transferred Item
  snapshots, linked destination record;
- **destination record** — `type = transfer`, destination role, the same Item
  snapshots, linked source record.

Both records carry enough immutable information to establish:

- common `transferId`;
- authoritative `clientId`;
- `fromProjectId` and `toProjectId`;
- source/destination role;
- counterpart Transaction ID;
- exact Item IDs and line snapshots;
- amount and category basis for each Item;
- whether each Item's allocation was open/uncollected or already paid at the
  Transfer boundary;
- initiation time and actor; and
- correction/cancellation provenance, if later needed.

The records are not two independent user actions. Neither may exist without its
counterpart.

## Item and Accounting Behavior

A direct same-Client Transfer means the client still owns the same Item. It must
not bill or refund that client merely because Ledger moved the Item between the
client's projects.

### Current Item state

The trusted operation:

- changes `item.projectId` from source to destination;
- clears a source-project `spaceId`, unless the operation explicitly supports a
  validated destination-space assignment;
- keeps the Item out of Business Inventory;
- preserves acquisition and paid provenance; and
- records the direct Transfer occurrence in Item history.

### Uncollected Item charge

If the Item has an open, uncollected charge, the same Client obligation follows
the Item rather than being canceled and recreated as a sale:

- remove it from the source project's active Invoicing queue;
- if it is on a created/sent source Invoice, remove the exact line and
  recalculate that live Invoice;
- place the same open charge in the destination project's Invoicing queue with
  preserved occurrence identity and amount basis; and
- do not create a source credit or destination purchase charge.

An Invoice remains project-scoped, so an Item line cannot silently remain on an
Invoice for the old project.

### Previously paid Item

If the Item was already paid:

- preserve the source project's paid Invoice, purchase Transaction, frozen Item
  line, and historical membership;
- create no Invoice credit and no new purchase;
- use the paired Transfer records to shift current project accounting
  attribution without rewriting paid history; and
- show the destination as the Item's current project while the old project
  remains visible in history.

This is analogous to a journal reallocation across one Client's projects, not a
new exchange of money.

## Budget Reallocation

If a $100 Item moves from Project A to Project B, Project
A's attributed spend decreases by $100 and Project B's increases by $100. Across
those two projects, the Client still has $100 of total recorded spend—not $0 and
not $200:

```text
source project effect + destination project effect = 0
```

The source side decreases and the destination side increases by the same
line-level recognized amount, but the authoritative budget source depends on
whether the Item was paid.

### Uncollected allocation

For an uncollected Item, budget attribution already comes from the open Item
charge:

- removing that charge from the source reduces the source's invoicing/unpaid
  segment;
- moving the same charge to the destination increases the destination's
  invoicing/unpaid segment; and
- the paired Transfer records are audit evidence and do not add a second budget
  contribution for that Item.

If the destination later collects the charge, ordinary Invoice collection moves
it from unpaid to paid in the destination without changing the destination
total.

### Paid allocation

For a paid Item, the original paid Purchase and Invoice allocation remain frozen
in the source project's history. The paired Transfer lines therefore carry the
reallocation:

- the source Transfer line contributes the negative frozen amount to the paid
  segment; and
- the destination Transfer line contributes the equal positive frozen amount
  to the paid segment.

The source/destination role supplies the sign; stored line amounts may remain
non-negative. A mixed bulk Transfer must retain this paid-versus-open behavior
per Item rather than applying one mode to the whole batch.

For each Item, the recognized amount should be:

- the current open charge amount if uncollected; or
- the frozen paid Item-line allocation if collected.

The paired records freeze those line-level amounts so later Item-price edits do
not create drift. All transferred project Item allocation remains Furnishings.
An Additional Requests tag is an overlay and requires an explicit rule about
whether project-specific tag state follows the Item.

## Trusted Atomic Operation

The app and MCP call one trusted operation with an idempotency key. Inside one
database transaction or equivalent atomic unit, the server must:

1. load source project, destination project, Client, Items, open charge state,
   and relevant Invoice/paid snapshots;
2. prove both projects belong to the same account and same non-null `clientId`;
3. prove all Items still belong to the source project;
4. compute and freeze every Item's accounting basis;
5. update any live source Invoice and move open Invoicing membership;
6. update current Item placement and clear incompatible Space membership;
7. write both linked Transfer Transactions and provenance;
8. update/reconcile affected project budget sources; and
9. commit everything or nothing.

A retry with the same idempotency key returns the original result. Concurrent
sale, return, Invoice collection, Item-price edit, Client reassignment, or
second Transfer must cause a retry or fail closed rather than producing partial
history.

## Migration

Current projects store only `clientName`. Migration must be additive:

1. create the Client collection and tolerant readers;
2. generate normalized-name match suggestions for review, but do not make text
   equality an accounting authorization rule;
3. create/choose Clients and backfill `project.clientId` in reviewed batches;
4. keep `clientName` as a compatibility snapshot during rollout;
5. require `clientId` on all newly created projects;
6. keep Transfer disabled for unresolved projects; and
7. switch search, pickers, reports, MCP schemas, and project editing to Client
   identity before removing direct `clientName` editing.

Homonyms, spouses/households, trusts/companies, punctuation differences, and
renamed Clients make blind one-name-one-Client migration unsafe.

## Implementation Impact

### Current code reality

- Swift `TransactionType` currently decodes `purchase`, `sale`, `fee`,
  `expense`, `paymentToBusiness`, and `return`.
- MCP currently exposes Purchase, Return, and Payment to Business to normal
  writers, creates Sale through inventory workflows, and reads several legacy
  values.
- Invoice collection currently creates `paymentToBusiness`, so changing the
  enum without changing collection would immediately write invalid target data.
- Swift and MCP Project models currently store only `clientName`; there is no
  Client collection or `project.clientId`.
- Project creation/editing, cards, search, reports, contract setup, MCP
  projections, and schema descriptions consume `clientName` directly.
- MCP lineage already recognizes a `transferred` movement kind, which may be
  reusable provenance vocabulary, but no paired Transfer Transaction model or
  same-Client validation currently exists.
- Firestore rules currently give account members broad Project access and have
  no Client collection or paired-Transfer invariant.

These facts make additive Client migration and tolerant Transaction readers
mandatory. Replacing the enum first would strand existing data and writers.

At minimum this direction touches:

- Swift and MCP transaction enums, normalization, filters, display, exports,
  tests, and legacy readers;
- Invoice collection, which changes target output from `paymentToBusiness` to
  `purchase`;
- the Project model, creation/edit forms, validation, service protocols, cards,
  search, reports, invoices, and contract setup;
- a new Client model, repository/context, pickers, archive flow, MCP tools,
  schema description, rules, and indexes;
- Item bulk actions and a same-Client destination picker;
- trusted paired-Transfer creation in iOS/backend/MCP rather than client-side
  independent writes;
- Invoice live-line recalculation and paid-history preservation;
- budget calculations and Cloud Function summaries for signed paired effects;
- lineage/provenance, transaction detail, audit, correction, and concurrency
  behavior; and
- production migration, reconciliation, and stale-client write rejection.

## Decisions Still Required

1. **Created/sent Invoice policy.** The current target says live Invoices update;
   confirm whether a Transfer may edit a sent Invoice or must require the user
   to remove/recall the line first.
2. **Additional Requests tag.** Confirm whether a project-specific tag follows
   the Item to the destination or is cleared/reselected.
3. **Destination Space.** Decide whether bulk Transfer can assign destination
   Spaces immediately or always clears Space for later assignment.
4. **Corrections.** Define reversal/correction UX for a completed Transfer
   without deleting either paired record.
5. **Later return or ownership change.** Confirm which project hosts a later
   client credit after a paid Item has passed through one or more same-Client
   Transfers. The recommended rule is the Item's current project, with the
   credit basis traced through the Transfer chain to the original frozen paid
   line.

## Acceptance Invariants

- New Transaction writes globally use only `purchase`, `return`, or `transfer`.
- Purchase and Return are interpreted relative to the owner of their scope;
  Transfer is project-only.
- A project `purchase` always corresponds to client money paid.
- A project `return` always corresponds to money actually received by the
  client.
- A `transfer` never claims cash moved and never creates Invoice demand.
- Every Transfer has exactly two linked records or none.
- Transfer destinations share the exact same non-null `clientId`.
- Client-name text is never used as authorization.
- The selected Items never pass through Business Inventory.
- Source and destination project effects are equal and opposite, so the
  recognized amount across the Client's projects remains unchanged.
- An uncollected Transfer moves one open budget source; the Transfer records do
  not count that amount a second time.
- A paid Transfer preserves the original paid record and uses equal negative and
  positive Transfer allocations to reattribute it.
- Paid history remains frozen while current Item placement changes.
- The operation is atomic, idempotent, origin-aware, and safe under retries.
