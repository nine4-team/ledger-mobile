# Item Creation and Accounting Link

Status: core product model approved; target Item shape and hard-cutover import pending
Last updated: 2026-08-31
Program: [Ledger Accounting Redesign](../plans/ledger-accounting-redesign/README.md)
Source handoff: [Item Intake and Linking](../plans/ledger-accounting-redesign/item-intake-handoff.md)
Production safety: [Compatibility and Rollout Plan](../plans/ledger-accounting-redesign/production-compatibility-plan.md)

## Purpose

Ledger needs one understandable way to create a physical Item even when the
designer does not yet know its receipt, price, payer, Transaction, or billing
route. The Item can be completed and connected to accounting later without ever
being presented as a fake draft that must be converted into a real object.

This spec replaces the target product model previously called Quick Draft,
Proto Item, or Needs Assignment. Existing `protoItems` data and pre-update
client behavior remain compatibility requirements during rollout.

## Product Vocabulary

- **Add Item** opens the one Item-creation wizard.
- **Quick** describes completing the lightweight first portion of that wizard.
  It is not a separate entity, writer, or creation pathway.
- **Unaccounted For Items** are project Items not yet connected to their
  accounting destination.
- **Accounted For Items** are connected either to a client-paid project Purchase
  or to the project's billable Items list.
- **Link** is the action that establishes that connection.

Do not expose **proto item**, **draft**, **conversion**, **promotion**, **Needs
Assignment**, **Assign Item**, **Unlinked Items**, or **Linked Items** as target
product language.

## Unified Item-Creation Wizard

All Item entry points use the same form state, validation model, and final Item
writer. The product may render it as one expandable screen or two sequential
steps, but there is no separate Quick Add form that writes a different object.

### First: familiar minimum Item fields

The fields used by the former proto-item capture experience appear first so the
flow remains familiar and fast:

- photos;
- name;
- notes;
- quantity; and
- contextual project and optional Space when already known.

This first portion defines the minimum savable Item experience. Quantity may
default to one, and project context may be supplied by the screen that opened
the wizard. The exact hard-validation rule among name, photo, and note must be
made consistent before implementation: the shipped full Item form accepts name
or image, while the proto form accepts image or note. Do not silently require
all three.

### Then: optional and accounting details

The user may continue in the same wizard to add:

- SKU;
- vendor/source;
- purchase price;
- project price;
- market value;
- status;
- payer guidance;
- acquisition Purchase; and
- the accounting Link described below.

Saving after the minimum portion creates the same real Item identity that later
detail and Link operations update. Continuing through optional details must not
create a second Item or replace the first Item's ID.

### Entry contexts

- From a project, the Item starts in that project and may receive a Space.
- From Business Inventory, the Item starts with `projectId == null`.
- From a Transaction, the wizard may preselect that Transaction only when its
  scope and type are eligible; the user still sees the same Item wizard.
- From images or an MCP capture tool, imported media and extracted fields seed
  the same wizard/writer rather than creating a separate product object.

## Accounting-State Rule

This terminology is project-scoped.

A project Item is **Accounted For** when at least one authoritative relationship
exists:

1. it is attached to the actual client-paid project Purchase that paid for it;
   or
2. it has a billable Item charge/credit occurrence in project Invoicing,
   whether available to invoice, on a live Invoice, or frozen as paid history.

Otherwise it is **Unaccounted For**.

The state is derived from authoritative relationships rather than a mutable
`isAccountedFor` boolean. Space, status, name completeness, price completeness,
Invoice selection, and Invoice sent state do not determine it. A paid Item
remains Accounted For after its active charge leaves the billables queue because
the frozen occurrence and paid membership still exist.

Project Items displays **Unaccounted For Items** first and **Accounted For
Items** below. Search, Space assignment, media editing, and ordinary physical
Item details are available in either section.

Business Inventory does not use this project accounting projection merely
because an Item lacks a project Link. Inventory acquisition completeness is a
separate concern.

## Link Flow

Opening **Link** asks:

> Who paid for this Item?

- **Client paid**
- **Business paid**

There is no **Not sure yet** choice. Closing the flow leaves the Item
Unaccounted For without side effects. The UI must not label either branch “Sell
from Business Inventory.”

Space remains optional and may be set before, during, or after Link. The review
screen states the exact accounting destination and effect before commit.

## Link Routes

### Client paid

The user chooses the Purchase in the current project that records the client's
actual payment. Only eligible project Purchases are offered. Transactions from
another project and Business Inventory are invalid for this branch.

The trusted, idempotent Link operation atomically:

1. validates that the Item still belongs to the project and is Unaccounted For;
2. validates the selected Purchase's account, project, type, and mutability;
3. creates the authoritative Item-to-Purchase relationship;
4. reconciles the Item's project category with Furnishings or the approved
   target category rule;
5. preserves Item identity, media, notes, quantity, and Space; and
6. makes the Item appear as Accounted For.

This branch creates no Invoicing demand because the client already paid.

### Business paid

The user may choose the Business Inventory Purchase that records 1584's vendor
payment, but that selection is optional. The UI may offer creation of the real
inventory Purchase as a separate, explicit action. Ledger must never fabricate
a vendor, amount, or Purchase in the background.

The trusted, idempotent Link operation atomically:

1. validates that the Item still belongs to the project and is Unaccounted For;
2. associates acquisition evidence with the selected inventory Purchase when
   one was selected;
3. creates one positive open Item charge under **Invoicing → Items** at the
   approved project-price basis;
4. records hidden acquisition, placement, and sale provenance using the target
   occurrence model;
5. attributes the open charge to Furnishings budget progress;
6. preserves Item identity, media, notes, quantity, and Space; and
7. makes the Item appear as Accounted For.

No project Transaction is created. Later whole-Invoice collection creates the
one lump-sum project Purchase and freezes the Item occurrence membership. An
associated Business Inventory Purchase remains inventory-scoped and is never
repriced by the project charge.

The target representation for missing acquisition evidence when the user Links
without selecting an inventory Purchase remains an open schema decision. It
must be explicit and reconcilable, not invented evidence.

## One Item Identity

The Item in Project Items and the Item represented in Invoicing are one physical
Item record. The billable Item charge is a separate accounting occurrence with
its own signed amount, category, Invoice state, and paid-history relationships.
It references the Item ID; it is not a second “billable Item.”

Receipt parsing, MCP automation, or legacy migration may later reveal duplicate
evidence for the same object. **Reconcile Existing Item** is a separate audited
identity/evidence operation, not a normal Link step. It must choose one surviving
Item ID, merge media/evidence deterministically, redirect only mutable
relationships, and preserve paid history.

## Target Real-Item Requirements

The new version stops writing new `protoItems`. Its ordinary `items` model must
therefore safely represent an Unaccounted For project Item.

The target model must allow:

- project placement without a Transaction relationship;
- an enabled Furnishings `budgetCategoryId` on a project Item even though
  category alone does not make the Item Accounted For;
- no billable occurrence yet;
- optional prices, vendor, SKU, status, and Space;
- the minimum identifying evidence approved for the wizard;
- zero budget contribution until an authoritative accounting relationship
  exists; and
- later atomic Link without changing Item identity.

The current Swift service already permits a categorized project Item with no
Transaction, and the UI already has a **No Transaction** correction state. The
target wizard should reuse that compatible shape: assign the project's enabled
Furnishings category automatically and leave `transactionId` null until Link.
The MCP create path currently rejects that shape and must be brought into
agreement with the app.

The remaining compatibility problem is accounting projection, not Item decode.
At least one shipped billing summary treats every project Item purchase price as
spent even when `transactionId` is null. New Unaccounted For writes must
therefore remain disabled in shared production until old-client arithmetic is
tolerant or a required-version/authority cutover is active.

The accounting state should be derived. If a cached field is added for query
performance, it is a repairable projection with server-side verification, not
the source of truth.

## Legacy Proto-Item Source Migration

The new version retires proto-item creation. Before hard cutover, the existing
Firebase app and its production structures continue operating unchanged while
the separate Supabase/PowerSync target is built and tested.

Before the source freeze:

- keep `accounts/{accountId}/protoItems/{protoItemId}` documents intact;
- keep proto-item Storage paths and attachment cleanup behavior intact;
- keep Firestore and Storage rules permitting the existing valid old-client
  operations;
- keep required composite indexes;
- keep current Firebase Swift and MCP decoding tolerant of legacy fields and
  statuses;
- keep current Firebase MCP tools functional until the hard-cutover window;
- do not rename or repurpose existing proto fields with incompatible meaning;
  and
- do not bulk-delete converted or open proto records.

The target app does **not** dual-read Firebase and contains no proto runtime
repository. Rehearsals import immutable Firebase export fixtures into isolated
target staging. At hard cutover, Ledger freezes Firebase writes, imports the
final delta, and resolves every legacy proto to exactly one target Item or an
explicit blocking quarantine result before target authority opens.

Resolution stores durable source-to-target correlation. Existing
`protoItem.convertedItemId` is honored when valid; the target migration journal
records the source proto ID and surviving Item ID. Retries return the same Item.
Media copying or path reuse must be explicit so migration cannot duplicate or
orphan attachments.

Old proto writers are rejected only as part of the rehearsed hard-cutover
source freeze, after open proto records and pending work are audited and the
O-022 rejection/recovery procedure is ready. This is operational source control,
not a Firebase implementation of the redesigned Item model.

## Pre-Cutover and Stale-Client Boundary

The current Firebase app has no Unaccounted For/Accounted For sections, its MCP
rejects some target Item shapes, and its Billing Summary can count an unlinked
priced Item incorrectly. Those facts are migration/parity evidence, not a
reason to add target behavior to Firebase.

Before cutover, target writers operate only in isolated Supabase/PowerSync
environments and the production Firebase app continues unchanged. At cutover,
the final source export and target activation are separated by a fail-closed
Firebase write freeze. O-022 must prove how already-shipped offline clients are
quiesced, how late source writes are rejected, and how pending/rejected work is
recovered. The target does not solve this with a Firebase adapter, tolerant v2
reader, dual write, or an intermediate Firebase redesign release.

## Atomicity and Concurrency

Creation, Link, legacy resolution, and reconciliation are trusted idempotent
operations. They must fail without partial records when any validation fails.

At commit, validate:

- account and project scope;
- current Item identity and placement;
- current accounting state;
- selected Purchase existence/type/mutability;
- occurrence uniqueness;
- category eligibility;
- price requirements for a Business-paid charge;
- live Invoice membership; and
- authority/schema version.

Retries cannot create a second Item, charge, Purchase association, occurrence,
or media copy. Concurrent Link, deletion, project move, Transfer, Invoice
collection, and price edit require transaction/precondition tests.

## MCP and Automation

MCP Item creation uses the same minimum-field contract and real Item writer as
the app. It must not keep creating proto items merely because its old tool is
named Quick Draft.

During compatibility:

- legacy quick-draft tools remain available to old callers;
- new tools expose Item creation and Link terminology;
- target Link is one trusted idempotent command per route;
- automation may suggest payer, Purchase, duplicate, or details but never Links,
  migrates, or merges silently; and
- deployed MCP changes must remain backward compatible until the authority
  cutover.

## Required Tests

- Minimum-field creation writes one real Unaccounted For Item.
- Adding optional details through the same wizard preserves Item ID.
- Space changes never change accounting state.
- Client-paid Link uses only an eligible current-project Purchase.
- Business-paid Link with and without a selected inventory Purchase creates one
  charge and no project Transaction.
- Link retry is idempotent.
- Link races with delete, move, Transfer, collection, and price edit fail or
  serialize safely.
- Existing open proto record imports to exactly one target Item under retries.
- Proto migration preserves media, notes, quantity, Space, and correlation.
- The current Firebase app and MCP remain unchanged and functional before the
  hard-cutover window.
- Target-only Item shapes are written only to isolated target environments
  before cutover; no Firebase client can observe them.
- Final source freeze rejects late legacy writes according to the tested O-022
  recovery contract.
- No Unaccounted For Item contributes to budget, Invoice, Transaction
  completeness, reports, or exports.

## Open Decisions

1. Is the unified wizard one expandable screen or two steps?
2. What is the exact minimum hard-validation rule among name, image, and note?
3. Does the wizard retain a non-authoritative payer hint before Link?
4. What record represents missing Business Inventory acquisition evidence after
   Business-paid Link without a selected Purchase?
5. What exact schema separates acquisition, placement, open occurrence, live
   Invoice membership, and paid history?
6. What exact O-022 quiescence/rejection/recovery mechanism protects the final
   source export from late legacy writes?
7. What exact bulk-import and quarantine policy resolves every legacy proto,
   and when is the old source writer frozen?
8. What is the exact audited duplicate/evidence reconciliation workflow?
