# Capability Dossier — Projects, Clients, Settings, and Reference Data

Status: reviewed static characterization; 36 of 52 target-relevant surfaces are
exactly target-mapped. Sixteen Project deletion, Client correction and shared
reference-data writer surfaces remain honestly withheld on O-024–O-026;
implementation remains unauthorized

## Outcome

An authorized account member can work offline with an account-scoped Client
directory, create and manage Projects that belong to one authoritative Client,
use stable account reference data, and customize personal Project presentation
without ambiguous identity, partial multi-write success, orphaned history, or
cross-user preference leakage. Project and Client IDs—not display names—own
relationships and authorization. Reference data remains configuration; it does
not become accounting evidence merely because a label is selected.

## Boundary

This dossier owns:

- Client identity and lifecycle;
- Project identity, Client relationship, archive/rename and current notes;
- Project setup as one durable operation, including selected category
  allocations and attachment handoff;
- account budget-category definitions and Project enablement/allocation;
- per-principal Project display preferences;
- vendor/source suggestions; and
- reusable Space-template definitions.

It does not own Item movement, Transfer accounting, Fee installment accounting,
budget arithmetic, Space CRUD, report projections, or attachment bytes. It
defines the contracts those capabilities consume and links cross-boundary source
evidence without claiming ownership of their final mapping.

## Source Surfaces

### Project, Client, and note path

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-E1A771F6A409`, `SWIFT-27CA6EAC7092` | `ProjectService`, protocol | Generic Firestore Project get/create/update/delete/listener operations; creation accepts free-text `clientName` |
| `SWIFT-A3AB0F29E150`, `SWIFT-5B59D74F6B13` | `ProjectNotesService`, protocol | Nested Project-note subscribe/create/update/delete |
| `SWIFT-7500FDB4FDB6`, `SWIFT-3D3C4156BE8B` | `Project`, `ProjectNote` | Firestore-shaped Project/free-text Client fields, denormalized budget summary, legacy notes, and separately authored note documents |
| `SWIFT-1DA3D2CE9B31` | `ProjectContext` | Nine independent Project listeners, in-memory financial filtering, note mutations, Project archive/delete, and derived budget state |
| `SWIFT-58A14BD25578`, `SWIFT-CF459111B7BB` | create/edit Project flows | Three-step Project/category/budget forms; dismiss before independent Project/category/media writes finish |
| `SWIFT-E23DAF7A18FA` | `ProjectsListView` | Active/archived list, alphabetical cards, per-user pin listeners and denormalized budget preview |
| `SWIFT-A9748507A27A`, `SWIFT-D73C92887393` | Project detail composition | ID-based route resolution, broad Project context activation, edit/archive/delete/export and current Client-name display |
| `SWIFT-7DC1AEC51D21` | `NotesTabView` | Device-side newest-first note display, legacy note card, add/edit/delete UX |
| `SWIFT-DCB56234B246`, `SWIFT-4F3C3856E659`, `SWIFT-42B77ABFD098` | cards and pickers | Display/search/select Projects using Project name and copied `clientName`; general destination picker excludes archived Projects but has no Client identity |
| `SWIFT-038E6D4248AF`, `SWIFT-48DE39470AF0` | pure Project calculations | Required free-text Client validation plus archive/search/sort and budget-card ordering |
| `TEST-E591BE8A4B58`, `TEST-3D0D949763A1` | existing Swift tests | Free-text Client validation, archive/search/sort and budget-card calculation coverage |

There is no current Client model, collection, service, picker, rule, query,
index, or MCP command. `Project.clientName` is the only implemented Client
representation.

### Settings and reference data

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `SWIFT-AFBB07058144`, `SWIFT-8926C720D04A` | budget-category service/model | CRUD for account categories plus type/archive/order/system metadata |
| `SWIFT-BAFED6656104`, `SWIFT-51D84FD65ADE` | Project category and Fee installment service/model | Project category enablement/allocation plus a separate Fee-installment writer combined in one source file |
| `SWIFT-093E5E4F8D20`, `SWIFT-B6C3B72884E1` | Project preferences | Per-user/per-Project pinned-category listeners and one merge write |
| `SWIFT-17BB6ABA1400`, `SWIFT-87F9C321FCB3` | vendor defaults | One ordered string array, default seeding, normalized add-if-missing and listeners |
| `SWIFT-4637466F7F73`, `SWIFT-3875BEEAD657` | Space templates | Template CRUD and create-from-Space copy of notes/checklists |
| `SWIFT-850F643150CE` | `AccountPresetsService` | Unreferenced wrapper that initializes only vendor defaults |
| `SWIFT-2E174120940E`, `SWIFT-9CF3A4F84903` | settings/budget protocols | Firebase-listener and untyped dictionary-shaped service seams, with unrelated identity and Fee APIs mixed together |
| `SWIFT-8375C283D4E5` | Settings root | Local theme preference, role-gated tabs, preset screens, Firestore debug link, and a direct signout bypassing the account-session lifecycle |
| `SWIFT-8D312DD816C5`, `SWIFT-58AED31D6D0B` | category settings/form | Create/edit/archive/unarchive/reorder categories, with each reorder row written independently |
| `SWIFT-1E0A38FC6F25`, `SWIFT-E60A204F472E` | vendor settings/pickers | Add/remove/reorder string suggestions; repeated view-local listeners and silent write failures |
| `SWIFT-E00DB27DF0BA` | template settings | Create/edit/hard-delete/reorder templates; each reorder row is an independent task |
| Cross-boundary Space creation/detail callers | `NewSpaceView`, `SpaceDetailView` | Template selection says no templates are available; Save as Template reports success while performing no write; final surface disposition remains in the Spaces dossier |

`BudgetProgressService`, Fee installments, Category-dependent accounting,
Spaces, and downstream vendor consumers remain final owners of their respective
business behavior. This dossier only fixes the configuration boundary they
consume.

### MCP, Functions, rules, and queries

| Surface IDs | Source | Current responsibility |
|---|---|---|
| `MCPMOD-8FC7F6247E2F` plus Project tools | `tools/projects.ts` | Account-wide list/get, item count, budget calculation, direct create/update/archive via Admin SDK |
| `MCPMOD-7774C2CE6D09` plus note tools | `tools/project-notes.ts` | Direct add/list/full-scan substring search of nested notes |
| `MCPMOD-CA75CFB7F29D` plus category tools | `tools/budget.ts` | Category list, Project allocations, Transaction-derived spend, direct enable/update |
| `FUNCTION-2F49CACBCFB6` | `createProject` | Callable Project creation with category seeding and a per-user Furnishings pin; current static review found no explicit account-membership check inside this Admin-SDK handler |
| Project/preset/preference rules | `firebase/firestore.rules` | Any account member can CRUD Projects, notes, presets, categories, templates and any user's Project preferences |
| query catalog | generated/static query evidence | Broad account Project listener; Project child listeners; active/archive equality; note order/limit on MCP only; preference and vendor listeners; Project-scoped Item/Transaction scans |

The app's direct Project creation does not call the callable Function, so two
current Project creation semantics coexist. The MCP has no Client capability and
can freely edit `clientName`. Admin-SDK access bypasses Firestore rules and does
not share one target authorization policy with the app.

### Migration evidence

- The fail-closed source profilers enumerate Projects, nested categories,
  Fee installments, notes, preferences and preset subcollections, but production
  shapes/counts remain unconfirmed until the read-only profile runs.
- `migration/src/supabase-reader.ts`, `types.ts`, and `transform.ts` describe a
  historical Supabase-to-Firebase migration. They contain useful legacy shapes,
  including free-text `client_name`, JSON Project budgets, vendor arrays and
  Space templates, but they are reverse-direction source evidence—not the new
  target importer or schema authority.
- Existing category audits/repairs prove that IDs, types, missing Project
  enablement rows and denormalized summaries have drifted in real operational
  history. The target importer must classify those variants; it must not trust
  the cached `budgetSummary` as canonical.

## Current Observable Behavior and Defects

### Projects and Clients

1. A Project is created locally with a generated Firestore ID and free-text
   Client name. Project, selected category allocations and hero media are three
   independent workflows. The form dismisses after the first write, suppresses
   later errors, and can leave a Project without intended categories or media.
2. Editing similarly dismisses before Project and category-diff tasks complete.
   One part may succeed while another fails, with no durable operation result or
   repair state.
3. Project and Client names may be changed together as ordinary fields. Matching
   text is used for display/search but cannot establish that two Projects belong
   to one Client.
4. Archiving hides a Project while preserving children. Hard deletion removes
   only the Project document and explicitly permits orphaned Items,
   Transactions, Spaces, nested records and references.
5. Project detail is assembled from independent listeners. Cached data may be
   useful offline, but readiness/completeness and partial-history state are not
   represented.
6. Legacy Project notes may live on `project.notes`; newer notes are nested
   documents. App sorting uses optional client `createdAt`; MCP ordering uses
   Firestore `createdAt desc`. There is no stable tie-break, revision or common
   conflict/audit contract for edit/delete.

### Settings and reference data

1. Budget category definitions are shared account configuration, while Project
   category rows enable a category and optionally allocate cents. Current create
   flows turn an omitted amount into zero even though the spec distinguishes
   enabled-without-budget (`null`) from explicitly zero.
2. Category names/types/order and Project allocations are directly writable by
   every account member. System-category protection, name uniqueness, type
   change dependency checks and financial permission are not enforced at the
   backend boundary.
3. Reordering categories or templates launches one independent write per row;
   interruption or concurrent edits can leave duplicate/partial ordering.
4. Project preference rules scope only by account membership, not by path UID.
   Any member can read or mutate another member's pin document if its path is
   known. Missing listener data is flattened to nil/empty rather than a readiness
   or authorization result.
5. Vendor suggestions are one mutable string array. Concurrent add/remove/
   reorder is last-write-wins over the entire array, stable identity is absent,
   and write errors are routinely suppressed. A suggestion is not a canonical
   Vendor identity; Transactions/Items retain free-text source snapshots.
6. Template management exists, but New Space never loads templates and Save as
   Template performs no write while displaying success. `createFromSpace`
   copies checked state even though the product spec requires template items to
   start unchecked. Template deletion is hard despite the model/spec supporting
   archive.
7. The Settings root directly signs out, bypassing the pending-operation/media
   session-ending contract captured in the identity dossier.

## Product and Spec Reconciliation

| Authority | Assessment |
|---|---|
| `client-identity-and-project-transfers.md` / D-003–D-006 | Canonical target authority for Client ID and the required Project relationship. Free-text source behavior is migration evidence only |
| `invoice-centered-project-accounting.md` | Canonical target budget/accounting boundary constrains Project/category projections; current cached summary mechanics are not authority |
| `projects.md` | Shipped UX remains useful, but Firestore paths, free-text Client validation, partial background writes and orphaning hard delete are current-state behavior, not target requirements |
| `budget-management.md` | Category intent, Project enablement and nullable-versus-zero allocation remain useful current-product evidence. Personal pins, the `overall` sentinel, missing/empty/no-pin defaults and Project-detail/card fallbacks require O-040; Transaction-only arithmetic and blanket last-write-wins do not govern the target |
| `spaces.md` | Template definition/apply/save behavior remains intended; static review confirms current creation/save callers are stubs and create-from-Space does not reset checks |
| `financial-access-controls.md` | Server/download enforcement remains required. Current account-member-wide preset and preference permissions are insufficient |
| A-003/A-004 | Target vendor selection remains proposed until the vertical spike; contracts below do not authorize target DDL or production migration |
| O-024/O-025/O-026/O-040 | Project deletion, Client correction/merge, reference-data administration and personal Project budget-pin outcomes are recorded blockers rather than guessed behavior |

## Behavior Decisions

| Classification | Decision |
|---|---|
| Preserve | Project ID/name/description/archive; Project list/detail/cards/search; one Client owning multiple Projects; Project notes with authorship/source; account category definitions; per-Project enablement/allocation; free-text vendor/source capture with reusable suggestions; Space templates; offline access to synchronized scope. Existing personal pins remain source evidence pending O-040 rather than a preservation decision |
| Correct | Free-text Client as identity; partial create/edit success; orphaning Project delete; cross-user preference access; broad unvalidated setting writes; system-category mutation; null-to-zero loss; array/reorder races; false-success/silent-error UI; template checked-state copy; no-op template callers; direct Settings signout |
| Improve | Stable local IDs; durable operation receipts; explicit readiness/partial-history state; atomic Project setup/configuration; revision/precondition conflicts; stable note ordering; archive-first lifecycle; stable ordered reference entries; one authorized query/command contract shared by app and MCP |
| Redesign | Project selects/creates an authoritative Client; Client rename is separate from Project rename; Project Client reassignment and Client merge are explicit correction workflows; target category/budget projection uses the approved accounting model rather than cached Firebase summary mechanics |
| Retire | Firebase types and `[String: Any]` application contracts; independent listener bags as the domain boundary; direct `clientName` editing; generic Project hard delete that leaves orphans; unused AccountPresets wrapper; target reliance on legacy `budgetSummary`; fake Save as Template success; reverse migration as target importer |
| Open | O-024 persisted Project deletion; O-025 Client reassignment/merge; O-026 reference-data administrators; O-040 whether personal pins survive plus typed targets, missing/empty/no-pin defaults, Project-detail/card fallbacks and lifecycle/cleanup; production Client-name clustering and orphan/reference variants until profiling |

## Target Observable Contract — Backend Neutral

1. `ClientID`, `ProjectID`, note/reference IDs and operation IDs are stable and
   can be allocated before connectivity. Names are mutable display values and
   never relationship or authorization keys.
2. Creating a Project requires one existing or newly created authorized Client.
   The accepted local operation durably records the Project, Client
   relationship, selected categories and exact nullable allocations together.
   Attachment bytes follow the media durable-receipt contract; a media failure
   is visible without invalidating a valid Project.
3. `RenameProject`, `UpdateProjectDetails`, `RenameClient`, `ArchiveProject` and
   `ArchiveClient` are distinct commands. `ChangeProjectClient`/Client merge are
   unavailable until O-025 defines correction, history and Transfer effects.
4. A normal delete cannot orphan children or accounting evidence. Archive is
   always safe; any physical Project deletion waits for O-024 and an
   authoritative dependency preflight.
5. Local Project/Client lists expose freshness, authorization and scope
   readiness. Detail may render partially synchronized data only with an
   explicit incomplete-history/readiness state.
6. Project notes have stable IDs, immutable creator/creation evidence, explicit
   edit revision/audit metadata, deterministic `(createdAt, id)` ordering and
   authorized tombstone/delete semantics. Offline retry cannot duplicate a
   note.
7. Category definitions use stable IDs and explicit active/system/type/order
   state. System categories and semantically dangerous type changes are handled
   by trusted commands. Project enablement preserves the distinction among no
   row, enabled/no allocation, and explicit zero; every supplied allocation is
   exact, non-negative integer-currency `Money`. The target does not inherit the
   source UI's arbitrary 32-bit maximum.
8. Updating Project details and the complete selected-category/allocation set is
   one idempotent conflict-aware operation, not a fan-out of silent writes.
9. Verified provider-free Project-preference read/update values are provisional
   primitives, not canonical approval that personal pins survive. If O-040
   retains the feature, reads/writes are limited to the authenticated principal
   (or an explicitly approved administrator), partitioned by account/environment,
   and use the approved typed targets, missing/empty/no-pin default, Project-
   detail/card fallback and archived/deleted-reference policy.
10. Vendor suggestions are ordered account configuration with stable identity
    or an equivalent conflict-safe ordered-set contract. Selecting one writes a
    free-text source snapshot; it does not silently create a canonical Vendor or
    rewrite historical sources.
11. Space templates can be created, edited, archived, reordered, applied to a
    new Space and created from an existing Space. Applying or capturing a
    template resets every checklist item to unchecked. Reorder is one durable
    operation with one result.
12. App and MCP use the same authorized commands and read models. No service
    credential, Admin SDK, or client-side filter expands authority.
13. Routine Settings signout invokes the identity dossier's session-ending
    lifecycle and cannot silently discard pending structured or media work.

## Port and Command Taxonomy

Target-neutral application contracts may now be designed around:

- `ClientQuerying`, `ProjectQuerying`, `ProjectNoteQuerying` and
  `ReferenceDataQuerying` local read ports;
- `CreateClient`, `RenameClient`, `ArchiveClient`;
- `CreateProject`, `RenameProject`, `UpdateProjectDetails`, `ArchiveProject`,
  and `ConfigureProjectCategories`;
- `AddProjectNote`, `EditProjectNote`, `RemoveProjectNote`;
- `CreateCategory`, `UpdateCategoryDefinition`, `ArchiveCategory`,
  `ReorderCategories`;
- `UpdateProjectPreferences`;
- `AddVendorSuggestion`, `RemoveVendorSuggestion`, `ReorderVendorSuggestions`;
  and
- `CreateSpaceTemplate`, `UpdateSpaceTemplate`, `ArchiveSpaceTemplate`,
  `ReorderSpaceTemplates`, `CreateTemplateFromSpace`.

These names separate stories and authorization boundaries. They are not a
promise that each command becomes one public database function or table.

## Security and Sync Requirements for Later Target Mapping

- RLS and Sync Streams authorize account rows from trusted membership, never
  user-editable metadata or a copied account ID alone.
- Personal preference download/write scope includes the authenticated principal
  predicate, not merely account membership.
- Reference-data mutations use the O-026 role/capability decision; read access
  is separately scoped so forms can work offline without granting write access.
- Client/Project/notes/reference rows carry immutable account ownership; update
  policies include both existing-row and resulting-row checks.
- Security-invoker queries/views retain RLS. Any privileged handler performs
  explicit principal/account/capability checks and grants no default public
  execution.
- The selected account's Clients, active/archived Projects, necessary category
  definitions, personal preferences and bounded notes are available locally.
  Historical/large note search may use an explicit on-demand stream, but local
  Project detail must state if history is incomplete.

## Migration Contract

1. Profile/export every Project, Project child, preference and preset namespace
   plus account members and cross-collection Project references. Record counts,
   hashes, field variants, orphans and decode failures.
2. Produce normalized Client-name suggestions, but require reviewed Client
   correlation. Homonyms, households, companies, punctuation and renamed
   Clients cannot be auto-merged by text equality.
3. Every target Project maps to one target Client or an explicit unresolved
   quarantine result. Transfer remains disabled for unresolved Projects.
4. Preserve source Project IDs where safe, free-text `clientName` as a legacy
   display/source snapshot, and immutable source correlation. Current Client
   display resolves from Client identity; paid/report snapshots are not
   rewritten on Client rename.
5. Reconcile Project children and references. A missing Project is not silently
   synthesized or dropped; it receives an approved relink/quarantine decision.
6. Preserve legacy Project note text and nested notes with deterministic source
   IDs and ordering evidence. Empty/invalid author or timestamp values are
   reported, not invented without an explicit mapping.
7. Preserve category IDs, type/archive/system metadata, Project enablement and
   null-versus-zero allocation. Rebuild budget projections from approved
   canonical sources rather than importing `budgetSummary` as authority.
8. Preserve source preference documents losslessly as migration evidence while
   O-040 is open. If pinning is retained, transform only under the approved
   target/default/fallback/lifecycle policy, prevent cross-principal leakage,
   and report stale category/Project IDs rather than silently dropping them.
9. Preserve vendor suggestion spelling/order and template content, normalize
   template checklist state according to the confirmed unchecked invariant, and
   record every semantic correction.
10. The old Supabase-to-Firebase transformer is never executed as the target
    importer. New imports are source-Firebase-to-isolated-target, restartable,
    idempotent and reconciled by source correlation.

## Required Tests

### Domain and offline

- create existing/new Client plus Project and nullable category allocations
  offline; restart; observe one durable receipt and one Project identity;
- failed media or one rejected allocation never creates silent partial success;
- Client rename updates current display but not frozen Invoice/report snapshots;
- Project rename does not change Client identity; name equality never enables
  Transfer;
- archive/unarchive works offline and syncs idempotently; prohibited delete
  leaves every child/reference unchanged;
- multi-device note add/edit/remove uses deterministic order and conflict state;
- category enablement distinguishes absent/null/zero across restart and sync;
- interrupted category/template/vendor reorder applies once or reports a
  conflict, never a partially ordered success;
- template apply/create-from-Space resets checks and works from synchronized
  local data; and
- Settings signout follows pending-work protection.

### Authorization and MCP parity

- cross-account Client/Project/note/reference reads and writes fail;
- if O-040 retains Project preferences, one member cannot read/write another
  principal's rows and no render-only fallback writes data;
- restricted member download exposes no protected category/financial metadata;
- system-category and unauthorized preset mutations fail in app and MCP;
- MCP cannot create/update a Project with arbitrary Client text or account ID;
- Client reassignment and physical Project deletion remain unavailable until
  their approved commands exist; and
- query/list results are stable, bounded and use the same archive/readiness
  semantics locally and through MCP.

### Migration

- every source Project maps to exactly one target Project and reviewed Client or
  explicit quarantine;
- all Project references/children, notes, preferences, category allocations,
  vendor suggestions and templates reconcile by count/hash/source ID;
- duplicate Client-name suggestions never become authorization without review;
- orphan, missing timestamp, invalid category, stale pin and template checked
  variants are fixture-tested and reported; and
- a second import after interruption creates no duplicate Client, Project,
  note, preference or reference row.

## Dossier Outcome

- **Ready for target-independent mapping:** IDs/read models, Client/Project
  boundary, archive/rename commands, Project setup receipt, note ordering,
  category enablement, vendor/template configuration, error/conflict taxonomy
  and migration correlation. Verified preference primitives remain available
  as representational evidence, but pin product outcomes are not mapped.
- **Ready for a bounded spike:** offline Client+Project creation, local query
  readiness, one atomic Project configuration command and ordered-reference
  conflict behavior using synthetic data. Preference security can be exercised
  only as a nonauthoritative fixture while O-040 remains open.
- **Blocked for final schema/writer policy:** O-024, O-025, O-026, O-040, A-003/A-004
  spike approval, production shapes, and final target identity/authorization
  decisions from A-007/A-016 where session state intersects offline writes.

No Firebase adapter, Firestore redesign, Supabase table/RLS policy, PowerSync
Stream, production read, or migration is authorized by this dossier alone.
