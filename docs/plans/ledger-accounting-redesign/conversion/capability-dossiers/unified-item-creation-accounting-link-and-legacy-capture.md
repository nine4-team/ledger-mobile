# Capability Dossier — Unified Item Creation, Accounting Link, and Legacy Capture

Status: reviewed static characterization; 16 of 33 target-relevant surfaces are
target-mapped or later. Seventeen schema/validation/Link/import/projection/
retention surfaces remain honestly withheld on their named decisions; O-021 is
UI-only and does not block architecture mapping or implementation sequencing.
The provider-free Project Item accounting-section read boundary is separately
controlled by `project-item-accounting-section-contracts`; its two target-only
surfaces are verified at exact implementation commit `92e0b565`.

## Outcome

An authorized user can create a physical Item quickly, see that same Item
immediately offline, add details without changing its identity, and later Link
it to the truthful accounting route. Project Items clearly separates
**Unaccounted For Items** from **Accounted For Items** using authoritative
relationships. The target has one Item writer and no proto/draft writer.
Existing Firebase `protoItems` are immutable migration-source evidence during
target development and become real target Items through the rehearsed import at
hard cutover.

## Boundary

This dossier owns:

- the one target Item-creation command and staged wizard;
- minimum Item identity/evidence validation;
- Item detail updates that do not represent financial or physical movement;
- Project Items accounting-state projection and Link entry point;
- Client-paid and Business-paid Link commands;
- local extraction/tag suggestions used to seed Item fields;
- quantity identity semantics;
- explicit duplicate/evidence reconciliation requirements; and
- import and correlation of legacy Firebase `protoItems`.

It does not own attachment byte durability, Space lifecycle, inventory/project
movement, Invoice collection, receipt parsing, general reporting, or the final
occurrence schema. It consumes those capabilities through the media dossier,
Space dossier, inventory/provenance dossier, and Invoicing dossier.

## Source Surfaces

### Item service, model, and validation

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-C593225376EB`, `SWIFT-47AEDE21C63C` | `ItemsService`, protocol | Generic Firestore Item CRUD/listeners, price/category normalization, Transaction back-reference maintenance, bulk metadata writes, photo-annotation cleanup and hard delete |
| `SWIFT-2B5DD377E0BB` | `Item` | One Firestore-shaped record combining physical identity, placement, one overloaded `transactionId`, prices, category, status, media and inventory-entry snapshots |
| `SWIFT-8BA5197CA887`, `TEST-322BEAB07F90` | `ItemFormValidation`, tests | Full form requires name or image and permits nonnegative optional prices |
| `SWIFT-07FE72314E4C`, `SWIFT-265DE17B71EF`, `TEST-FCBA68605B98` | tag extraction | On-device image/OCR/barcode candidate extraction and deterministic SKU mutation policy |
| `FUNCMOD-ED4C25A2C78E`, `FUNCTION-E58CC96C3CEF`, `FUNCTION-8741B9D80FCC`, `FUNCTION-EE4FDF40EC7B` | current Functions | Firebase price-floor enforcement, Transaction membership/lineage repair and movement-price side effects; already characterized as source behavior, not target implementation |
| `RULE-D3CFB25D03AD` | current Item rule | Account-member Item access plus partial price/category constraints; already characterized for target redesign |

`ItemsService.createItem` allows a categorized project Item without a
Transaction, while the MCP create path rejects it. The service also contains
generic `setTransaction`/`clearTransaction` methods that conflate accounting
Link, correction, and membership maintenance. Its bulk writer commits in
500-row chunks, so a large logical action can partially succeed.

### App creation and Project Items

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-D2EEB690D6AD` | `NewItemView` | Full Item form, direct Transaction listeners, category reads, Item creation, direct Firestore accounting batches, legacy proto conversion and media enqueue |
| `SWIFT-068E43CFFCC5` | `ItemDraftCaptureSheet` | Separate photo/note-first path that writes `ProtoItem`, extracts tags and queues proto media |
| `SWIFT-0B434663295C` | `ItemsTabView` | Project Item list plus separate Needs Assignment proto section, conversion/merge/delete, generic Transaction association and bulk mutations |
| `SWIFT-1B50ECDA7CA1`, `SWIFT-A24C5FE4E6AD` | proto detail/card | Edit the separate proto record, show routing hints, merge/promote/delete and direct media mutations |
| `SWIFT-7F24BFB8649C`, `SWIFT-F377448F2608`, `SWIFT-4F4F708AA0DD`, `SWIFT-618D86C999C1` | shared list/cards/calculations | Search/filter/group/select Item presentation; price/category/status/Invoice badges but no authoritative Accounted For projection |
| `SWIFT-AB578AEF4330`, `SWIFT-236679C7D427` | Item detail | Live Item detail and a broad action catalog that always offers delete and exposes generic set/clear Transaction operations |
| `SWIFT-63EEC4FFD5ED` | `ItemEntryFlowView` | Transaction-first inventory Item entry followed by optional sell-to-Project flow |

The in-progress release source is materially safer than older behavior in a few
places, including explicit assignment-route explanations and some atomic
Firestore batches. Those changes are valuable behavior evidence. They do not
make the view-layer Firestore composition or separate proto identity a target
architecture.

### Legacy proto service and model

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-08066A63BD11` | `ProtoItem` | Separate capture identity, open/in-review/converted lifecycle, route hint, candidate matches, photos, extraction and conversion correlation |
| `SWIFT-8B52C90F1043`, `SWIFT-BB61FBAE2B1D` | proto service/protocol | Firebase proto CRUD/listeners, conversion markers and media queue metadata |
| `RULE-4DD3733CBE59` | current proto rule | Existing account-member CRUD needed by the current Firebase app before hard cutover |
| source query contract | app/MCP proto listeners | Active, project, inventory and Transaction-scoped legacy reads; target importer must reproduce source selection without becoming a runtime target reader |

`assignmentHint`, `isFromInventory`, `candidateTransactionId` and
`candidateItemId` are provisional evidence, not accounting authority.
`convertProtoItem` marks the source only after another path creates or merges an
Item; several UI callers suppress failures, so current conversion can report or
appear complete after only part of the intended workflow.

### MCP Item and quick-draft paths

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `MCPMOD-82DC4C25B1B8` plus Item tools | `tools/items.ts` | Direct Admin-SDK list/search/get/create/update/bulk/delete plus media operations; project create requires a Transaction, unlike Swift |
| `MCPMOD-B1238289755F` plus quick-draft tools | `tools/quick-draft-items.ts` | Legacy proto list/get/search/audit/create/update/delete/review/promotion and optional merge into an existing Item |
| existing MCP tests | Item invariants, price, list, copy-name and quick-draft promotion suites | Useful current behavior and edge evidence; they do not prove the target one-writer/Link contract |

The MCP promotion path can assemble an Item, Project Purchase, acquisition
mutation, lineage edge and proto conversion in one Firebase batch. The app has
similar but separately implemented composition. This duplication is exactly
the domain-authority problem the target command layer must remove.

### Migration evidence

- The fail-closed source profiler enumerates `items`, `protoItems`,
  Transactions, lineage, Invoices and Storage references, but production
  counts/shapes remain unconfirmed until the approved read-only profile runs.
- Existing proto source IDs, `convertedItemId`, candidate IDs, timestamps,
  statuses, assignment hints, photos and extraction payloads are migration
  inputs. None may be silently treated as a confirmed payer or acquisition.
- Current Item `transactionId` is route-dependent and insufficient to separate
  acquisition, client payment, placement, open charge and paid history. Import
  must classify the referenced Transaction and preserve ambiguity explicitly.
- Historical Supabase-to-Firebase migration code is reverse-direction evidence
  only and is not the target importer.

## Current Observable Behavior and Defects

1. Users see two creation paths: full Item and Quick Add. They write different
   document types and require a later conversion/merge step.
2. The full form requires name or image and a positive purchase/project price;
   Quick Add requires image or note and allows missing price. The approved
   target wants one minimum save contract, but the exact rule is still open.
3. `NewItemView` mixes UI state, direct Firestore queries, category validation,
   Item persistence, Transaction creation, lineage creation, acquisition
   mutation, proto conversion and media enqueue. App and MCP independently
   encode variants of the same business stories.
4. Normal linked creation can return generated Items before the Firestore batch
   commit finishes; its default commit failure path only prints. Other create
   branches dismiss before asynchronous media succeeds.
5. Quantity handling is inconsistent. Current `NewItemView` creates `quantity`
   Item documents while also leaving the original quantity on each copy;
   legacy proto/MCP promotion generally creates one Item with a quantity. The
   product spec requires one Item record with the quantity value unless an
   explicit physical-copy operation intentionally creates separate identities.
6. The current Project Items screen groups real Items and proto records by
   storage type, not by the target accounting relationship. Space, Invoice
   badges and Transaction presence are available, but no canonical
   Unaccounted For/Accounted For read model exists.
7. Generic set/clear Transaction actions can represent client-paid Link,
   correction or accidental association without forcing the user/business
   story. Business-paid Link is currently modeled in places as an inventory
   sale that creates a Project Purchase, which contradicts the target rule that
   no Project Transaction exists before Invoice collection.
8. Current `Item.currentSource` documents Project-to-Project movement as two
   hops through inventory. The target same-Client Transfer is direct paired
   provenance and is outside ordinary Item creation/Link.
9. Delete is broadly exposed. App paths suppress some delete errors; MCP removes
   the Item and current Transaction back-reference but does not establish the
   target history/occurrence/paid-evidence policy. A target generic hard delete
   would be unsafe.
10. Legacy proto deletion differs by caller: the iOS flow also attempts media
    deletion, while the MCP explicitly leaves Storage media behind.
11. App and MCP use account-member/direct Admin access respectively and do not
    share one target authorization/operation policy.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| D-018 | One wizard, one real Item writer and one stable Item ID are authoritative; the separate proto path is target-retired |
| D-019/D-020 | Accounted For is derived from a client-paid Purchase relationship or Item charge occurrence; Link has only Client paid / Business paid and dismiss has no effect |
| D-021/D-024 | Client-paid Link selects a real current-Project Purchase; Business-paid Link creates an open charge and no pre-collection Project Transaction; inventory-sale wording is hidden provenance |
| D-022/D-023 | One physical Item identity is referenced by Invoicing; Space is optional and independent of accounting state |
| D-025/A-017 | Firebase proto code stays unchanged as the running source before cutoff. The target has no proto writer, Firebase adapter, runtime dual-read or Firebase implementation of target Link |
| `items.md` | Stable physical identity, quantity-on-one-record, price floor, item detail and list behavior remain useful. Firestore paths, generic Transaction actions and always-available delete are current mechanics |
| `proto-item-capture.md` | Unified wizard and Link product model are authoritative. Its former runtime dual-read language is corrected in this change to the rehearsed hard-cutover import model |
| media dossier/O-023 | Stable attachment references and durable local media receipts are consumed here; byte deletion policy is not re-decided |
| O-016–O-022 | Acquisition evidence, optional hint, proto import, duplicate reconciliation, activation, UI layout and stale-source-writer recovery remain named blockers |
| O-027 | The exact minimum identifying evidence among name/photo/note is now a recorded product blocker instead of being silently selected by one existing form |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Stable Item identity; Project/Inventory placement; optional Space; name/notes/SKU/vendor/status/prices/quantity/media; local extraction suggestions; search/filter/detail; price floor; fast repeated field capture; explicit user confirmation for accounting |
| Correct | Two writers/identities; inconsistent validation; quantity multiplication; false-success and swallowed errors; generic Transaction association; Project Purchase created for Business-paid Link; broad hard delete; provisional hints treated as route evidence; media cleanup divergence; app/MCP policy drift |
| Improve | Locally allocated IDs; immediate durable local visibility; staged completion on one Item; deterministic operation receipts; explicit readiness/freshness; one authorization policy; command-level audit/retry/conflict results; bounded local query models |
| Redesign | Project list sections derive accounting state; Link uses story-specific commands; business-paid demand is an occurrence; legacy proto is transformed at cutover; duplicate matching is a separate audited reconciliation workflow |
| Retire | Target `ProtoItem` model/service/UI/writer/tools; target Needs Assignment/Assign/Promote vocabulary; view-layer Firestore batches; generic Item `setTransaction`/`clearTransaction` as public stories; target dependence on Firebase listeners, rules, Functions or Admin SDK |
| Source only | Existing Firebase proto paths/tools/rules, current movement/linkage implementations, old reverse migration and repair/audit utilities after source freeze |
| Open | O-016–O-022, O-023 where media deletion is involved, O-027 and production Item/proto shape/profile evidence |

## Target Observable Contract — Backend Neutral

1. `CreateItem` accepts a caller-generated operation ID and Item ID, account,
   destination Project or Inventory, optional Space, the approved minimum
   evidence and any supplied optional fields. Acceptance persists one real Item
   locally before returning.
2. Quick completion and extended completion are stages of the same form state
   and writer. Saving the minimum and later adding details preserves the Item
   ID. The target never writes a proto/draft entity.
3. Quantity defaults to one and is stored on the one Item. Separate Item IDs
   are created only by an explicit copy/materialization operation that states
   how many distinct physical identities are intended; it never multiplies
   both record count and quantity.
4. A project Item can exist without a Purchase relationship or billable
   occurrence. It receives the approved enabled Furnishings/category placement
   but contributes zero spend until an authoritative Link relationship exists.
5. Project Items derives two ordered collections from local authoritative
   relationships: Unaccounted For first, Accounted For second. Space, status,
   category, Invoice selection and detail completeness cannot change sections.
6. Dismissing Link performs no write. `LinkItemAsClientPaid` and
   `LinkItemAsBusinessPaid` are separate idempotent commands with distinct
   validation and effects.
7. Client-paid Link validates the Item and selected current-Project Purchase,
   creates the Item-to-Purchase relationship once and creates no billable
   occurrence.
8. Business-paid Link optionally associates real inventory acquisition
   evidence, creates exactly one open positive Item charge at the approved
   basis, and creates no Project Transaction. Missing acquisition evidence is
   explicit and waits for O-016; it is never fabricated.
9. Link preserves Item identity, media, notes, quantity and Space. A successful
   retry returns the original operation/result IDs. A conflicting second payer
   route fails with the current authoritative state.
10. Ordinary Item detail updates cannot mutate accounting or movement
    relationships. Placement, Link, reconciliation, Transfer, return and
    correction are separate commands with their own authorization and audit.
11. Extraction/OCR candidates seed fields but never Link, merge, move, price or
    create financial evidence without the approved human/automation command.
12. Reconcile Existing Item is explicit and audited. It chooses a surviving
    Item ID, merges evidence according to O-019, redirects only mutable
    relationships and never rewrites frozen paid history.
13. A generic hard delete is unavailable for an Item with accounting,
    movement, Invoice, media-retention or audit dependencies. Removing an open
    charge/physical placement uses the owning story-specific command. Empty,
    never-linked mistaken Items follow a recoverable tombstone policy.
14. App and MCP invoke the same commands and read models. Automation receives
    typed validation/conflict results and cannot bypass confirmation or RLS
    through a service credential.

## Port and Command Taxonomy

Target-neutral application contracts may now be designed around:

- `ItemQuerying`, `ProjectItemAccountingQuerying` and
  `ItemDetailReadModelQuerying` local read ports;
- `CreateItem`, `UpdateItemDetails`, `SetItemSpace`, `SetItemStatus` and
  `SetItemBookmark`;
- `LinkItemAsClientPaid` and `LinkItemAsBusinessPaid`;
- `ResolveLegacyProtoItem` as an importer/reconciliation operation, not an app
  creation command;
- `ReconcileExistingItemEvidence` after O-019; and
- `DiscardUnlinkedItem` only under the approved dependency/tombstone policy.

Inventory movement, Transfer, Return, Invoice collection and accounting
correction commands remain separate. These names do not imply one public RPC or
one table per command.

## Security and Sync Requirements for Later Target Mapping

- RLS and Sync Streams derive account access from trusted membership and
  immutable ownership; payload `accountId`, Project ID or user metadata alone
  never grants access.
- Normal Item detail updates cannot write accounting relationships, occurrence
  rows, paid memberships, provenance or source-correlation fields.
- Trusted Link handlers re-authorize account/Project, Item state, category and
  selected Purchase inside the same transaction that writes the result. Public
  execution is denied unless explicitly granted to the authenticated role.
- The selected Project stream contains Items, the relationship/occurrence
  evidence required to derive both accounting sections, eligible current
  Purchases for Link, Spaces, and open operation results. Inventory streams
  contain Items plus enough acquisition/lineage evidence to explain their
  history offline.
- Local reads expose synchronization readiness and incomplete-history state;
  absence of a row before stream readiness is not interpreted as Unaccounted
  For.
- Simple Item creation is locally optimistic and durable. Complex Link
  projection remains gated by A-015: the client may show a pending operation,
  but cannot invent accepted accounting state before the authoritative result.
- Item/media operations consume the encrypted local database, key and pending-
  work logout contract from the identity/media dossiers.

## Migration Contract

1. Export every Item and proto document plus referenced Project, Space,
   category, Transaction, Invoice/line, lineage, media and audit evidence from
   the frozen Firebase source. Record source IDs, hashes, variants and decode
   failures.
2. Import every current real Item once, preserving its stable source identity
   where safe. Classify overloaded `transactionId` by referenced Transaction
   semantics; unresolved or contradictory relationships enter quarantine and
   do not gain invented accounting effects.
3. Transform every non-converted/open legacy proto into exactly one target
   Item or an explicit blocking quarantine result. Converted protos correlate
   to their existing Item when valid and never create a duplicate.
4. Preserve proto name, notes, quantity, Space, photos, extraction, timestamps,
   author/source evidence and candidate IDs. Hints remain non-authoritative
   annotations; they never create a Purchase, occurrence, Link or merge.
5. Store durable source-to-target correlation sufficient for retry and audit.
   Re-running the same import returns the same target Item ID and attachment
   references.
6. Normalize contradictory quantity representations only under an explicit
   deterministic rule and report every changed source record. Never infer N
   physical copies from one quantity value and also retain quantity N on each.
7. Copy/reuse media through the media manifest with byte/reference hashes,
   ownership and verification. Do not delete Firebase source objects during
   import or rollback windows.
8. There is no target runtime dual-read of Firebase proto records. Rehearsal
   imports use immutable snapshots; the hard cutover freezes Firebase, imports
   the final delta, reconciles every proto outcome, then activates the target.
9. Late Firebase writes after the final export are rejected/recovered under
   O-022. They are not reconciled by adding a Firebase adapter to the target.

## Required Tests

### Domain and offline

- save the approved minimum offline, terminate/restart, and observe one Item ID
  in Unaccounted For with a durable operation receipt;
- continue optional details before/after restart and preserve that ID;
- create quantity greater than one and prove one Item row with that quantity;
- explicit copy creates distinct IDs without mutating source quantity/name;
- Space/detail/media changes never change accounting state;
- dismiss Link and prove no state, budget, occurrence or audit write;
- Client-paid Link rejects other-Project, inventory, wrong-type, canceled/frozen
  or changed Purchases and succeeds once under retry;
- Business-paid Link with/without acquisition evidence creates one occurrence,
  no Project Transaction, and no duplicate under retry;
- concurrent Link, move, delete/tombstone, price edit, Transfer and Invoice
  collection either serialize or return a typed conflict with no partial state;
- accepted offline Link remains pending across restart and follows the A-015
  authoritative-result policy on reconnect; and
- large bulk metadata updates have an explicit all-or-partial contract and
  resumable per-Item results rather than silent chunk success.

### Migration, security, and parity

- every source Item/proto is imported, correlated, quarantined or explicitly
  dispositioned; counts and hashes reconcile with zero unexplained loss;
- converted proto retries resolve to the same real Item;
- open proto import preserves notes, quantity, Space, media, extraction and
  author/timestamp evidence without applying its payer/candidate hints;
- app and MCP pass the same CreateItem and Link behavioral suite;
- cross-account Item, eligible-Purchase and operation-result reads/writes are
  denied, including resulting-row ownership changes;
- target Items cannot be mutated directly into a linked/paid state;
- PowerSync streams provide enough local evidence to derive both sections and
  explain Item accounting provenance offline; and
- source snapshots can be repeatedly imported into isolated target staging;
  target activation remains impossible while any final proto/import result is
  unexplained or O-022 is unproven.

## Outcome and Gates

The user-visible Item creation and Link outcomes are sufficiently characterized
to start target-neutral port and command design. Target Postgres tables, RLS,
Sync Streams and handlers remain gated by the complete occurrence/Invoicing
mapping, A-003/A-004 vertical spike, A-015 optimistic-operation result, O-016,
O-018–O-020, O-022, O-027 and production source profiling. This dossier does
not authorize a Supabase production migration, a Firebase refactor, or a
Firebase implementation of target Item behavior.
