# Capability Dossier — Inventory Provenance, Transactions, Receipts, and Corrections

Status: reviewed static characterization; 27 of 68 target-relevant surfaces are
target-mapped or later. Forty-one decision-sensitive movement, occurrence,
receipt, lifecycle and retention surfaces remain honestly withheld on their
named blockers. Full capability implementation remains unauthorized outside a
machine-ready bounded slice; the confirmed provider-free taxonomy/Transfer-pair
value foundation is separately controlled by
`transaction-taxonomy-and-transfer-identity`, and the bounded embedded-line/
exact-reconstruction boundary is implemented locally and controlled by
`non-item-receipt-line-reconstruction-contracts`.

## Outcome

An authorized Ledger user can record a real Purchase or Return in the scope
whose owner paid or received money, move a physical Item without fabricating a
cash event, transfer an Item directly between projects of the same Client,
capture an exact receipt, and correct a mistake without rewriting history.
Inventory and Project Item history remains explainable while offline. The app
and MCP invoke the same typed operations; neither assembles accounting by
mutating generic Transaction, Item, Invoice, or lineage fields.

## Boundary

This dossier owns:

- project- and Business-Inventory Purchase/Return capture;
- Transaction list, detail, validation, receipt reconstruction, cancellation,
  deletion and correction boundaries;
- physical Inventory/Project/vendor placement stories;
- inventory acquisition intent as planning metadata rather than money evidence;
- Item occurrence, lineage, origin and immutable price-basis requirements;
- same-Client Transfer integration and cross-Client movement routing;
- `NonItemReceiptLine` behavior inside Purchase/Return evidence;
- offline Transaction and Item-history read models; and
- migration of legacy Transaction/movement/lineage evidence.

It does not own Item creation/Link, attachment-byte durability, Client identity,
Invoice construction/collection, Expense/Fee lifecycle, budget presentation, or
the final Postgres occurrence DDL. It consumes those outcomes from the adjacent
capability dossiers and canonical product specs.

## Source Surfaces

### Swift services and models

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-1DCA8A4ADE51` | `InventoryOperationsService` | Large client-side Firestore composer for inventory-to-project, project-to-inventory, project-to-project, vendor Return association and scope correction; creates per-batch Transactions, Item mutations, lineage and paid-Item draft credits |
| `SWIFT-1178D1E9F474`, `SWIFT-57FFA664E36B` | `TransactionsService`, protocol | Generic Transaction create/get/update/delete/listeners, untyped field patches, category validation and cascaded Item scope/category mutation |
| `SWIFT-089405BED5D8` | `LineageEdgesService` | Direct LineageEdge creation plus on-demand Item/Transaction history reads with optional decoding and client-side timestamp sorting |
| `SWIFT-01C928A8B707` | `Transaction` | Firestore-shaped aggregate containing type, scope, current `itemIds`, payer/reimbursement routing, receipt fields, ingestion, derived completeness/audit and settlement links |
| `SWIFT-4C47C0D715F5` | `IncompleteReturnDetection` | Infers a partially processed physical return from Item status, Transaction type and absence of one lineage kind |

`Transaction.itemIds` currently means active membership in most writers. Items
are removed from earlier Transactions as they move and detail reconstructs some
historical membership from lineage. That is incompatible with frozen paid
membership and is insufficient authority for acquisition, placement, billing,
refund and history at the same time.

### Swift Transaction and movement UI

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-A7915475818E` | `NewTransactionView` | Multi-step Purchase/Return creation, payer and inventory-routing decisions, receipt upload ID allocation, tax/subtotal derivation and immediate dismiss/next-stage routing |
| `SWIFT-BDF8928A5FC7` | `TransactionDetailView` | Broad live detail surface combining Transaction, active/returned/sold Items, proto records, lineage, receipt media, completeness, creation, generic association, movement, correction and deletion |
| `SWIFT-04CC0C101EA4`, `SWIFT-674F92BED6F7` | Project/Inventory Transaction lists | Local filtering/grouping, selection, total, detail navigation and broad single/bulk deletion |
| `SWIFT-30289B39B988`, `SWIFT-19D2C873E96F`, `SWIFT-5BCE896008A3`, `SWIFT-736B5D34BF46`, `SWIFT-9226674CC889` | shared cards/filter/list/display calculations | Current type/status/category/source/item-count presentation and filtering |
| `SWIFT-3348465E2026`, `SWIFT-34855F53F580`, `SWIFT-E73BF270D7A4` | validation/next steps/audit | Type-only minimum submission, derived checklist and persisted completeness/variance presentation |
| `SWIFT-4003332541C1`, `SWIFT-582C58D417AA`, `SWIFT-CE425FC823BE` | edit/menu/reassign UI | Untyped ordinary field updates, whole-Transaction project correction and always-available delete affordances |
| `SWIFT-CD04095425B1`, `SWIFT-5E15CB2D9DF7`, `SWIFT-E613F00C92A4` | add/return/Transaction pickers | Same-scope association, cross-scope reassignment, Return-Transaction selection and conflict UI |
| `SWIFT-967F1C133CF5`, `SWIFT-E29B4124133A`, `SWIFT-99F937C57A47` | sell/return/reassign modals | User-facing entry points into the overloaded current movement operations |
| `SWIFT-D8ADF0266301` | `InventoryContext` | Independent Firebase listeners for Inventory Items, proto records, Transactions and Spaces |

The edit form currently submits `transactionType` and `hasEmailReceipt` keys,
while the persisted Transaction contract uses `type` and `receiptEmailed`.
This can make an apparent edit diverge from the fields normal readers decode.
Several movement/association callers dismiss immediately and only print or
suppress asynchronous failures.

### MCP modules and tools

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `MCPMOD-868A3F35EBC3` and Transaction tools | `tools/transactions.ts` | Admin-SDK list/get/search/create/update/bulk/cancel/delete plus media; current lists use unstable offset pagination and several reads reconstruct history from mutable arrays plus lineage |
| `MCPMOD-F5D411967411` and five movement tools | `tools/inventory-operations.ts` | Server-side variants of per-batch sell/return/two-hop movement with origin resolution, locked snapshots, dry runs and a 100-Item Firestore cap |
| `MCPMOD-DFECB1787DB7`, `MCPTOOL-9D1270611686` | whole-Transaction correction | Defensive dry-run planner and atomic correction of one ordinary Transaction plus exact active Item membership |
| `MCPMOD-D14DD1E83CFE` and purchase-intent tools | inventory purchase intent | Reads/updates optional intended Project/category metadata and corrects an Inventory Purchase into a current project-reimbursement model |
| `MCPMOD-A34D9491FE4`, `MCPTOOL-522654D35421`, `MCPTOOL-B1DC0447215A` | lineage tools | On-demand Item or Project movement reads with display-name resolution |
| `MCPMOD-B5A85B82D135`, `MCPTOOL-282034D0C8AF`, `MCPTOOL-BBB9B61F2EE8` | destructive Transaction deletion | Default-deny dependency scan, server-enforced human approval, serializable recheck, immutable tombstone and single/batch delete |
| `MCPMOD-4305DCB6FD6B` | inventory utility | Source-label and current origin inference shared by current tools |

The MCP correction and deletion planners are valuable safety evidence. Their
Admin-SDK access and Firestore-specific implementation are not target ports.
The target must retain the safety outcomes inside the same authoritative
handlers and RLS/capability model used by the app.

### Current Functions, rules, queries and tests

- `FUNCTION-EBFFD3F950A0` derives Transaction completeness/budget effects after
  writes; `FUNCTION-0CBF780A52CC` reacts to lineage; Item association and price
  Functions also repair or reprice related records. These asynchronously
  competing authorities are already classified for target redesign.
- `RULE-6852D375E671`, `RULE-FC994C6C2FEA` and
  `RULE-D3CFB25D03AD` allow current Firebase clients to compose parts of the
  aggregate directly. Admin MCP writes bypass those rules.
- The current query catalog proves nullable Project scope, many equality
  filters, array membership, broad client-side filtering, on-demand lineage,
  and mostly unordered offset pagination. It does not define target query
  ordering or prove deployed production index coverage.
- Swift and MCP suites cover important current invariants: origin-aware amount
  basis, batch atomicity, return-to-source provenance, whole-Transaction
  correction blockers, deletion preflight/tombstones, type normalization,
  display and incomplete-return detection. They are source evidence, not proof
  of the redesigned accounting stories.

## Current Observable Behavior and Defects

1. Inventory-to-Project movement creates a project Purchase even when the
   client has not paid. Target behavior is physical placement plus one open
   Item charge and occurrence, with no project Transaction before collection.
2. Project-to-Inventory movement creates a project Return for a physical move,
   regardless of whether client cash was actually refunded. Target behavior
   depends on billing state: remove uncollected demand, or create a pending
   credit after payment; only actual cash refund creates Return.
3. A project-origin Item acquired by 1584 creates a legacy Sale Transaction in
   the source project. `sale` is not a target type. The real 1584 acquisition,
   project-demand change and physical placement are separate facts.
4. Project-to-Project movement always uses an Inventory two-hop. Same-Client
   movement must instead be one direct paired Transfer; cross-Client movement
   uses correlated removal/acquisition/new-charge provenance without sharing
   project accounting records.
5. `returnToProject` creates a Purchase while the user calls the action Return.
   This hides whether the action is restored placement, a new open charge, or
   actual money movement.
6. `returnToTransaction` and generic set/clear Transaction association let a
   physical return, vendor refund, Item membership repair and accounting
   correction converge on the same mutation shape.
7. Current origin resolution depends on mutable `transactionId`, source labels
   ending in `" Inventory"`, `currentSource`, optional lineage and, for some
   legacy single-Item records, Transaction totals. Useful fail-closed branches
   exist, but there is no one authoritative occurrence chain.
8. Current lineage uses loose optional string fields and auto IDs. App writers,
   MCP writers and a Function can all produce evidence; no uniqueness key,
   revision, correlation contract or deterministic timestamp tie-break proves
   one complete history. Swift silently drops decode failures.
9. Movement caps and grouping are shaped by Firestore write limits. A 100-Item
   limit may remain a product/operational guard, but it is not backend-neutral
   behavior unless deliberately adopted.
10. Transaction creation can submit with only a type. Missing amount, source,
    date, category and receipt facts are represented on the canonical money
    record and later inferred through `isComplete`. The target has no approved
    minimum evidence or draft-versus-posted boundary yet.
11. Receipt completeness uses subtotal/tax/discount and a percentage tolerance;
    the accepted `NonItemReceiptLine` design instead reconstructs final amount
    in exact cents from physical Items plus signed nonphysical lines.
12. Generic Transaction updates can cascade Project/category changes to every
    currently attached Item, clear Spaces, or detach membership without naming
    the economic story. App edit keys can also miss their Codable field names.
13. MCP `cancel_transaction` can zero a Transaction's budget contribution with
    a note but without the dependency preflight used by deletion. App edit
    similarly exposes cancellation as a field toggle. This can leave active
    Item, Invoice or lineage relationships with canceled money evidence.
14. iOS deletion checks only current `itemIds`; MCP deletion checks many more
    dependencies and preserves a tombstone. The two clients therefore expose
    materially different safety contracts.
15. Lists and searches do not define stable ordering/cursor semantics. A broad
    client or MCP scan can return a different page under concurrent writes.
16. Current Inventory context can display cached Items and Transactions, but
    lineage is fetched on demand. A user offline at a job site cannot rely on a
    previously unseen Item history being locally explainable.
17. The proposed `vendor-credits.md` adds a fourth `Credit` Transaction type.
    That proposal predates and conflicts with confirmed D-001/D-007, so it
    cannot enter the target schema. Actual money returned by a vendor is a
    scope-relative Return; non-cash vendor credit still needs an explicit
    non-Transaction decision.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `invoice-centered-project-accounting.md` | Canonical target money-versus-open-demand boundary and collection ownership; current movement Transactions cannot define the target |
| `client-identity-and-project-transfers.md` | Canonical target Client identity, global three-type Transaction taxonomy and same-Client paired Transfer contract |
| `proto-item-capture.md` | Canonical target Link routes and one-Item identity constrain acquisition, occurrence and correction stories |
| D-001/D-002/D-007 | Target Transactions have exactly Purchase, Return and project-only Transfer. Purchase/Return name actual scope-owner money movement |
| D-003–D-006/D-017 | Same-Client Project movement is one direct atomic paired Transfer with equal/opposite allocation; matching names and Inventory two-hop are invalid authority |
| D-008/D-014 | Inventory-to-Project placement creates an Item charge and hidden occurrence, not a Project Purchase or user-facing movement record |
| D-010/D-011/D-015 | Invoice collection owns its one Project Purchase and frozen historical membership; later Item movement cannot rewrite it |
| D-016 | Nonphysical receipt components are stable signed receipt-line values, not fake Items or a fourth Transaction type |
| D-018–D-024 | Movement operates on the one physical Item identity and consumes the Link/accounting-state contract rather than generic `transactionId` mutation |
| `inventory-item-invoicing-lifecycle.md` | The eleven target stories are authoritative: open-demand removal, paid credit, resale, project-origin acquisition, return-to-source, direct Transfer, cross-Client route, correction and vendor refund stay distinct |
| `2026-08-30-correct-transaction-and-its-items.md` | Its fail-closed aggregate-validation and dry-run outcomes are useful. Its Firebase/project-reimbursement mechanics are current-source behavior, not a universal target `CorrectTransactionAndItems` command |
| `non-item-receipt-lines/design.md` | Accepted receipt reconstruction remains target direction; O-008/O-030/O-031 own its unresolved billability, rounding and Item tax-basis decisions |
| `vendor-credits.md` | Proposed fourth Transaction type is superseded for the redesign by D-001. Its evidence about cancellation versus physical return remains useful, but no target `Credit` writer is authorized |
| O-002–O-015 | Transfer, credit settlement, live Invoice and occurrence details remain blockers where their exact behavior changes a command |
| O-028–O-032 | Non-cash vendor credit, Transaction void/delete, receipt rounding/tax inheritance and canonical Transaction minimum evidence are recorded instead of guessed |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Scope-relative money meaning; vendor/date/amount/source/notes/payment evidence; physical Item identity; purchase/project price bases; explicit inventory intent; fast batch selection; dry-run previews for destructive/corrective work; explainable history; exact dependency preflight and immutable deletion evidence if deletion remains |
| Correct | Project Purchase fabricated by Inventory sale; physical movement fabricated as Return; two-hop same-Client movement; Sale/paymentToBusiness/fee/expense target writes; generic Return/association; source-label origin authority; optional/drop-on-decode lineage; type-only canonical money record; percentage receipt tolerance; field-name drift; silent async failure; cancellation without dependency validation; inconsistent app/MCP deletion |
| Improve | One operation ID and authoritative result per story; typed values instead of dynamic patches; deterministic cursor ordering; complete local provenance/readiness; conflict receipts; explicit pending/rejected UI; shared app/MCP validation and authorization; immutable line snapshots instead of reconstructing from mutable Item state |
| Redesign | Split placement, money, open billing, credit, Transfer and correction commands; store exact occurrence relationships; preserve historical Transaction membership; reconstruct final receipt totals from Items plus `NonItemReceiptLine`; make server transaction the only accounting authority |
| Retire | Target generic Transaction CRUD/update/bulk update; public `itemIds` replacement; current sell/return/reassign command names; project `sale`, `paymentToBusiness`, `fee`, `expense` and `to inventory` writes; target source-label heuristics; target client-written lineage; target Firebase Functions/rules/Admin SDK composition |
| Source only | Existing Firebase services, views, tools, rules, Functions, migration/repair scripts, legacy movement flags/snapshots, deletion tombstones and lineage after source freeze |
| Open | O-002–O-015, O-023 where attachments affect deletion, O-028–O-032, A-003/A-004/A-015 and production shape/profile evidence |

## Target Story and Command Taxonomy

Public operations name the event. They are not aliases over a generic
`CreateTransaction` or `ReturnItems` endpoint.

### Real money

| Story | Candidate command | Required effect |
|---|---|---|
| Client pays vendor directly | `RecordProjectPurchase` | One Project Purchase, receipt lines and immutable Item/line membership; no Invoicing demand |
| Client receives vendor refund | `RecordProjectVendorRefund` | One Project Return linked to the supported original evidence; optional physical-disposition link remains distinct |
| 1584 buys inventory | `RecordInventoryPurchase` | One Inventory Purchase/acquisition with Item and receipt evidence |
| 1584 receives vendor refund | `RecordInventoryVendorRefund` | One Inventory Return; physical vendor disposition is linked but not inferred |
| Client pays whole Invoice | `CollectInvoice` | Owned by Invoicing: one Project Purchase plus frozen collected contents |
| 1584 pays client cash against credit | `SettleClientCreditAsCashRefund` | One Project Return only when cash actually leaves 1584; blocked on O-003/O-004 |

Every money command validates positive final amount, scope, actor capability,
category/allocation evidence, operation ID and version. No caller selects a
fourth Transaction type.

### Physical placement and billing state

| Story | Candidate command | Required effect |
|---|---|---|
| Inventory Item enters Project | `PlaceInventoryItemInProject` | Move current placement, create new open positive Item occurrence/charge, preserve acquisition; no Project Transaction |
| Uncollected Item returns to Inventory | `RemoveUnpaidItemFromProject` | Move placement, reverse exact open occurrence/live Invoice membership, no credit and no Return |
| Paid Item returns to Inventory | `ReturnPaidItemToInventoryAndCreateCredit` | Preserve paid history, move placement, create one deterministic negative credit, no Return until cash |
| Project-origin Item acquired by 1584 | `AcquireProjectItemIntoInventory` | Record actual Inventory-side acquisition evidence when money/value changes, move placement, remove open demand or create paid credit; no project Sale type |
| Proven project-origin Item returns from Inventory | `RestoreItemToSourceProject` | Restore immutable source/basis and create a new open Item occurrence; no cash Purchase |
| Item sent to outside vendor before refund | `RecordItemVendorDisposition` | Record physical custody/status/provenance only; later money command links the refund |
| Same-Client Project movement | `TransferItems` | Direct placement plus exactly two linked Transfer records and billing/allocation changes atomically |
| Different-Client Project movement | `MoveItemBetweenClientsThroughInventory` | Correlated source demand/credit, Inventory custody/acquisition evidence and new destination occurrence without shared Project records |

The exact handler grouping may combine inseparable effects into one database
transaction. The vocabulary must still expose which physical, billing and cash
events occurred.

### Corrections, cancellation and deletion

- `CorrectPurchaseDetails` and `CorrectReturnDetails` operate only on fields
  allowed by the record's dependency/state matrix and always write audit
  evidence.
- `CorrectTransactionScope` is available only when evidence proves the original
  scope was a data-entry mistake and no downstream immutable history would be
  rewritten. It does not manufacture movement, demand or cash.
- `CorrectItemPlacement` repairs physical placement and occurrence state without
  changing money evidence. Before collection it updates live demand atomically;
  after collection it requires explicit credit/accounting-correction rules.
- `ReverseTransfer` is a paired append-only operation blocked on O-013; neither
  original Transfer half can be canceled or deleted independently.
- A dependency-aware `VoidTransaction` and any `DeleteSupersededTransaction`
  remain disabled until O-029. A field-level status toggle is not a command.
- Dry run is a query/plan receipt, not stale authorization. Execution reloads
  all versions and dependencies in the authoritative transaction.

## Target Observable Contract — Backend Neutral

1. Each accepted command has a caller-generated operation ID, immutable payload
   hash, actor/account, expected revisions where needed and one durable result.
   Same ID/same payload returns the original result; same ID/different payload
   conflicts.
2. Canonical Transaction values contain exactly Purchase, Return or Transfer.
   Legacy values remain import/read evidence and cannot be written by target
   app or MCP code.
3. Purchase/Return scope ownership is explicit and immutable after dependent
   history. A Project belongs to its Client; Business Inventory belongs to
   1584. Return cannot mean pending credit or physical placement alone.
4. Transaction line/membership evidence is stable historical evidence. Moving
   an Item later never removes it from an earlier paid/acquisition record.
   Current placement is queried separately.
5. Every Item sale/return/resale cycle has a unique occurrence identity, exact
   predecessor/reversal links, immutable scope/category/amount basis and a
   deterministic sequence. O-007/O-015 decide the final representation.
6. Receipt reconstruction uses physical line amounts plus ordered, stable-ID,
   signed `NonItemReceiptLine` values against final `amountCents`. No fake Item,
   percentage tolerance or silent tax inference closes a variance.
7. Creation/update/correction returns explicit missing-evidence, conflict,
   dependency, authorization and readiness results. UI cannot dismiss as
   successful merely because a local asynchronous task started.
8. Transaction list and history reads have documented stable ordering and
   cursor keys. Suggested default is effective event date descending, then
   authoritative creation time descending, then immutable ID descending.
9. Item history sorts by authoritative operation sequence/time plus immutable
   occurrence ID, never optional client timestamps alone. Decode/integrity gaps
   produce an incomplete-history state rather than disappearing.
10. App and MCP call the same authoritative operations. MCP automation never
    receives a service-role escape hatch around account capability checks,
    dependency validation, confirmation or immutable locks.
11. Current data corrections, migrations and reconciliation jobs use separate
    administrative capabilities and immutable evidence. They are not exposed as
    ordinary end-user CRUD.
12. No target operation reads or writes Firebase. Firebase documents and tools
    remain source evidence for isolated import and final cutover only.

## Local Read and Offline History Contract

The selected Project stream includes the Project, Client identity snapshot,
current Items, Purchase/Return/Transfer summaries and lines, open Item
occurrences/credits, relevant live Invoice membership, Spaces, operation
results and the provenance needed to explain every Item currently in that
Project.

The Inventory stream includes every current Inventory Item, acquisition line,
current placement/custody state, immutable inventory-entry basis, occurrence or
lineage chain needed to explain how it arrived, related Purchase/Return
summaries allowed by financial access, planning intent and open operation
results. A previously unseen current Inventory Item must not show a definitive
history while offline unless this evidence is locally complete.

Cross-scope historical detail may use a separate authorized history stream to
bound download size, but the core Project/Inventory streams retain enough
immutable snapshots and relationship IDs to explain current origin, amount
basis and last movement offline. Read models expose:

- `localState`: pending, accepted, rejected or synchronized;
- `scopeReadiness` and `historyReadiness`;
- missing/quarantined source evidence with stable reason codes; and
- restricted financial detail as unavailable, never as zero or nonexistent.

An optimistic complex operation may display its submitted plan and pending
state, but accounting projections cannot claim authoritative acceptance before
the trusted handler result. This remains gated by A-015 and the vertical spike.

## Security and Authoritative Mutation Requirements

- RLS derives account membership and financial capability from trusted rows;
  payload account, Project, Client, category, source label or local cache state
  never grants access.
- Normal table grants cannot directly insert/update/delete canonical
  Transaction lines, Transfer halves, paid membership, occurrences, lineage,
  correction audit, operation results or deletion evidence. Explicit
  authenticated handlers own those writes.
- Each handler re-reads scope ownership, Client identity, Item placement,
  occurrence/Invoice state, category enablement, dependent references and
  expected revisions inside the same Postgres transaction that commits all
  canonical effects and the result.
- Financially restricted members receive neither rows nor revealing counts,
  sums, provenance labels or Sync Stream membership. Server operations enforce
  the same capabilities as local queries.
- Destructive/corrective commands require a durable reason and, where product
  policy requires, a trusted human confirmation bound to the exact plan/version.
- Background jobs may verify projections and report drift; they do not race the
  command handler as an alternative accounting writer.

## Migration Contract

1. Export every Transaction, Item, Invoice/line, lineage edge, proto reference,
   repricing event, deletion tombstone, request marker, relevant Project/Client
   source and receipt attachment reference from the frozen Firebase source.
2. Preserve raw source type/status/scope/flags, field presence, source IDs,
   timestamps, hashes and decode errors before normalization.
3. Classify legacy `purchase`, `return`, `sale`, `paymentToBusiness`, `fee`,
   `expense`, `to inventory` and unknown variants using scope, payer, settlement,
   source, movement flags, Item/Invoice/lineage references and reviewed fixtures.
   Never map by type string alone.
4. Import evidence-backed project/inventory Purchases and Returns into the
   scope-relative target taxonomy. Invoice settlements become the collection
   Purchase relationship. Inventory movement Transactions become occurrence,
   placement, charge/credit and provenance evidence rather than target Project
   money records.
5. Reconstruct historical Item membership from both Transaction arrays,
   Item back-references, lineage, audit aggregates, inventory-entry snapshots,
   Invoice lines and known repair manifests. Record disagreement; do not choose
   the most convenient edge silently.
6. Generate deterministic occurrence/correlation IDs from source evidence and
   record every source-to-target relationship in the migration journal. Missing,
   duplicate or cyclic chains quarantine the affected relationship while
   retaining the Item and raw evidence.
7. Convert receipt components only when source evidence supports the exact
   signed line. Do not label residual amount as tax, shipping or discount from
   arithmetic alone. Record O-030 rounding treatment explicitly.
8. Incomplete current Transactions follow O-032: map to a canonical record only
   when minimum money evidence is met; otherwise import as review/quarantine or
   approved nonfinancial draft without budget effect.
9. Preserve canceled/deleted/tombstone evidence according to O-029 and media
   references according to O-023. Never resurrect a deleted source record as
   active merely because its tombstone has a snapshot.
10. Reconcile per account/scope/type, final money totals, signed receipt
    reconstruction, Item current placement, historical membership, occurrence
    chain completeness, Transfer pair cardinality, Invoice settlement links,
    attachments and every quarantined exception before activation.
11. Rehearse from immutable production-like snapshots in isolated staging.
    Production Firebase remains unchanged until final freeze/import/reconcile/
    activate; there is no Firebase adapter or target dual write.

## Required Verification

### Money and receipt stories

- offline project Purchase and Return submit/restart/retry with one result;
- offline Inventory Purchase and Return with correct scope owner;
- whole-Invoice collection creates its single Purchase and cannot be duplicated
  by the ordinary Purchase command;
- vendor physical disposition before refund creates no Return; later supported
  refund creates exactly one linked scope-relative Return;
- physical Items plus multiple increase/decrease receipt lines reconstruct the
  final amount exactly, including one-cent source discrepancy behavior;
- missing/duplicate receipt-line IDs, zero amounts, unexplained residual and
  fabricated Item lines reject consistently in app/MCP/import;
- legacy fourth types cannot be written through app, RPC, direct table access or
  MCP.

### Placement, occurrence and Transfer stories

- Inventory → Project creates placement/open charge/occurrence and no Project
  Transaction;
- unpaid Project → Inventory removes exact live demand and creates no Return;
- paid Project → Inventory preserves paid history and creates one credit under
  retries;
- return/resale cycles retain one Item identity and distinct occurrences;
- project-origin acquisition uses purchase-cost basis and return-to-source uses
  the immutable entry snapshot;
- same-Client movement creates exactly one Transfer pair without Inventory hop;
- different-Client movement cannot call Transfer and keeps accounting scopes
  separate;
- ambiguous, cyclic, missing or duplicate provenance fails closed with an
  incomplete-history result.

### Correction, deletion, security and offline reads

- permitted pre-history correction commits detail/placement/audit atomically;
- stale revision, paid history, live Invoice, movement or asymmetric membership
  blocks the wrong correction without partial writes;
- void/delete follows O-029, dependency recheck and immutable evidence; Transfer
  halves cannot be independently voided/deleted;
- app and MCP produce identical validation/authorization outcomes;
- cross-account, nonfinancial-member and direct-table attempts reveal no
  forbidden rows/counts and cannot forge evidence;
- Project and Inventory current Item histories are explainable after a fresh
  sync followed by complete network loss; absent history readiness never renders
  as a complete empty history;
- deterministic pagination has no duplicates or omissions across concurrent
  inserts when resumed from a cursor; and
- migration fixture reconciliation catches every type/scope/membership/amount/
  occurrence mismatch and never silently drops a corrupt edge.

## Exit Criteria for Target Mapping

This capability can advance from characterization to target mapping only when:

- O-007/O-015 approve occurrence and relationship authority;
- O-002–O-005/O-011–O-014 close Transfer/credit behavior required by enabled
  commands;
- O-008/O-030/O-031 close receipt billability, rounding and Item tax-basis
  behavior;
- O-028 resolves non-cash vendor credit without adding a fourth Transaction;
- O-029 defines Transaction void/delete policy;
- O-032 defines canonical minimum evidence/draft import behavior;
- the vertical spike passes A-003/A-004/A-015 for encrypted local data,
  Firebase Auth bridge if retained, and complex optimistic operations; and
- production-derived shapes are profiled read-only and representative source
  fixtures reconcile in isolated Supabase/PowerSync staging.

This dossier does not authorize DDL, RLS, Sync Streams, Supabase handlers,
PowerSync upload behavior, production reads/mutations, migration or cutover.
