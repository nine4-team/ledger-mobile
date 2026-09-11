# Decision Packet — O-026 Shared Reference-Data Authorization

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-08-31
Owners: Account Administration, Budget Categories, Space Templates, Vendors
Unlocks: 19 residual surfaces
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Approve or reject the following default capability policy:

> Shared reference data is readable only through visibility-safe Account
> projections and mutable only through typed, revision-safe commands. Owners and
> admins manage ordinary account categories and shared ordering. Financial
> category definition and Project budget allocation require a dedicated
> financial-configuration capability. Space-template management is owner/admin
> by default but may be explicitly delegated. Members who can capture
> Transactions may add a normalized vendor suggestion during ordinary work, but
> only reference-data administrators may rename/archive/merge/reorder the shared
> vendor list. System categories are never mutable by an app/MCP user.

This packet proposes default product authorization and target contracts. It is
not DDL, implementation authorization, or approval of Supabase/PowerSync before
the vertical spike.

## Confirmed Constraints

- Reference rows and preferences are Account-scoped; personal preferences are
  Principal-owned rather than shared Account authority.
- Category identity/meaning participates in accounting, budgets, Invoices and
  reports, so historical use must remain resolvable after display/lifecycle
  change.
- Financial-access restrictions apply to rows, counts, search, Sync membership,
  errors and operation results—not just visible settings screens.
- System category semantics cannot be ordinary user-editable configuration.
- Auth metadata or caller-supplied role/capability values never grant target
  authorization.
- App and MCP must use the same trusted commands and visibility-safe queries.

## Options

### Option A — Every Account member can CRUD all shared presets

Reject. It lets ordinary operational convenience writes alter financial meaning
and shared history.

### Option B — Owner-only administration for every reference family

Reject as unnecessarily restrictive. It prevents safe delegation and makes
ordinary capture-time vendor discovery dependent on an owner.

### Option C — Risk-specific capability matrix (recommended)

Protect financial/system semantics, allow owner/admin defaults with explicit
delegation for operational templates, and let authorized capture suggest a
vendor without granting shared-list administration.

## Why One “Account Member Can CRUD Presets” Rule Is Unsafe

The three families have different risk:

- category type, inclusion and allocation can change financial meaning;
- Space templates change shared operational defaults but not accounting; and
- vendor suggestions are convenience data naturally discovered during capture.

One broad CRUD permission either exposes financial configuration to every
member or makes ordinary vendor/template workflows unnecessarily administrative.
The target should authorize capabilities, not infer permission from a settings
screen or a caller-supplied role.

## Recommended Capability Matrix

The stored roles remain Owner, Admin, and Employee. Capabilities are trusted
membership data and may be narrowed/delegated by an Owner without changing the
role names.

| Action | Owner | Admin | Employee default | Delegable |
|---|---:|---:|---:|---:|
| Read allowed active category definitions | yes | yes | yes, visibility-filtered | no |
| Create/edit/archive/reorder ordinary category definitions | yes | yes | no | `manage_financial_configuration` only |
| Change category semantic type/exclusion after use | typed correction only | typed correction only | no | no |
| Mutate system category key/type/archive state | no | no | no | server migration/maintenance only |
| Enable existing category for a Project | yes | yes | no | `manage_project_budgets` |
| Set/change Project category allocation | yes | yes | no | `manage_project_budgets` plus allowed financial visibility |
| Read/apply active Space templates | yes | yes | yes | no |
| Create/edit/archive/reorder Space templates | yes | yes | no | `manage_shared_templates` |
| Add normalized vendor suggestion during authorized capture | yes | yes | yes | follows capture capability |
| Rename/merge/archive/reorder vendor suggestions | yes | yes | no | `manage_shared_reference_data` |
| Read/write personal Project pins/preferences | own only | own only | own only | no |

An Admin may be denied company-financial access only if the product later
supports that combination. If so, role alone does not restore category or
allocation visibility: both the mutation capability and the applicable
financial visibility must pass.

## Category Rules

- Category identity and semantic type are stable. Display name, color, ordinary
  description and order may be revised with expected revision.
- A category referenced by Transactions, occurrences, Expenses, Fees, Invoices,
  budgets, reports, migration evidence or allowed-member visibility cannot be
  physically deleted. Archive removes it from new selection while historical
  rows remain resolvable.
- Changing semantic type, overall-budget inclusion, or another accounting
  behavior after first use is not ordinary edit. Use a typed correction/migration
  plan that shows affected Projects, sources, reports and access grants.
- System categories have immutable key/type/ownership and are provisioned or
  versioned only by trusted server migration. Owners may not turn them into
  ordinary categories or archive them.
- Name uniqueness uses a normalized comparison within Account and active state;
  display casing is preserved. Merge requires an explicit dependency-aware
  command, not rename collision.
- Enabling a category and setting its Project allocation is one revision-safe
  Project configuration command. Reorder is one atomic ordered-set command, not
  independent row writes.

## Space-Template Rules

- Templates carry stable identity, name, notes, checklist definitions, active/
  archived state, revision and order.
- Applying a template creates a new Space/checklist snapshot and resets every
  checklist completion/assignment state. Later template edits never rewrite an
  existing Space.
- Archive removes a template from new selection while keeping prior application
  evidence resolvable. Physical delete is limited to an unsynchronized/never-
  applied local draft, if such a draft exists under the approved draft policy.
- `manage_shared_templates` can be delegated independently because templates are
  operational, not financial. Delegation itself remains an Account-admin command.
- Reorder is atomic and revision-safe across the complete submitted active set.

## Vendor-Suggestion Rules

- A vendor suggestion is a stable row, not a shared string array.
- Authorized Transaction/Item capture may call `SuggestVendor` with the entered
  display value. The handler trims/normalizes for identity, preserves reviewed
  display casing, and idempotently reuses an active match.
- Suggestion creation cannot alter an existing display value/order or reactivate
  an archived value. Those are administrator commands.
- Administrators can rename, merge, archive and reorder through typed commands
  with expected revisions and reference counts. Historical Transactions retain
  their captured counterparty/evidence snapshot and optional stable vendor link.
- Removing a suggestion from pickers never rewrites financial evidence.

## Authorization and Visibility

- Role, capabilities, financial access and allowed financial category IDs come
  from trusted active membership rows, not JWT user metadata or request payload.
- Employee readers receive all ordinary client-budget categories needed for
  authorized Project work. Company-revenue/fee categories are filtered by the
  existing full/limited/none financial-access policy, including counts/search/
  Sync membership.
- A mutation requires both its named capability and visibility of the exact
  category/template/vendor dependency. No write can move a row to another
  Account or convert its ownership/system status.
- Personal preferences are keyed by Principal and can be read/written only by
  that Principal through ordinary app/MCP use. Administrative repair is a
  separately audited capability.
- App and MCP invoke the same command handlers. A service identity records the
  human/agent Principal and cannot bypass the capability matrix.

## Conceptual Target Shape

| Family | Responsibility |
|---|---|
| account capability assignments | Trusted membership-scoped capability grants/revocations |
| `budget_categories` | Stable category definition, semantic type/system key, visibility class, archive/revision/order |
| `project_category_allocations` | Project enablement and optional integer-cent allocation with revision |
| `space_templates` and template checklist rows | Stable shared operational template and ordered definitions |
| `vendor_suggestions` | Stable normalized identity, display value, archive/revision/order and merge correlation |
| personal Project preferences | Principal-owned pins/preferences, never shared authority |
| reference-data events | Append-only create/revise/archive/reorder/merge/correction actor/reason evidence |
| operation/results | Idempotency, payload hash, expected revisions and durable outcomes |

Use immutable Account ownership, foreign keys, integer cents, explicit checks,
and stable client-generated IDs where offline creation is allowed. Index every
foreign key and RLS predicate. Use partial unique indexes for active normalized
names/keys and equality-first/keyset indexes for visibility-safe lists. Reorder
commands lock the owning Account/reference family and affected IDs in a stable
order and update the set atomically.

## Command and Query Contracts

- `CreateCategory`, `ReviseCategoryPresentation`, `ArchiveCategory`,
  `ReorderCategories`, and a separately gated `CorrectCategorySemantics`;
- `ConfigureProjectCategories` for the complete enabled/allocation diff;
- `CreateSpaceTemplate`, `ReviseSpaceTemplate`, `ArchiveSpaceTemplate`,
  `ReorderSpaceTemplates`, and `ApplySpaceTemplate`;
- `SuggestVendor`, `RenameVendorSuggestion`, `MergeVendorSuggestions`,
  `ArchiveVendorSuggestion`, and `ReorderVendorSuggestions`;
- visibility-safe category/template/vendor snapshot queries with stable cursors,
  revisions and readiness; and
- own-Principal preference query/update contracts.

There is no generic reference-data CRUD dictionary, raw array patch, per-row
fire-and-forget reorder, or caller-selectable Account/role override.

## Offline and Sync Behavior

- Active reference snapshots needed by the selected Account/Projects are synced
  before the UI claims pickers/configuration are complete. Readiness distinguishes
  complete, partial, restricted and stale.
- Offline create/revise/reorder submits a durable operation with expected base
  revision. Optimistic presentation is marked pending; reconnect conflict
  returns the authoritative set plus a typed resolution path.
- Category semantic correction and merge are not optimistically projected as
  accepted accounting changes. They require trusted result before downstream
  projections claim completion.
- Capability/financial revocation removes future downloads and follows the
  approved offline lease/local cleanup policy. A stale local role never grants
  server mutation.
- Vendor suggestion retries are idempotent under normalized identity and do not
  create duplicates after reconnect.

## Migration and Reconciliation

- Export category definitions/metadata, Project allocations, system/default
  pointers, Space templates/checklists, vendor arrays, personal pins and every
  reference from the immutable Firebase source.
- Map stable IDs where present. Generate deterministic IDs for array vendors and
  malformed/duplicate entries with raw ordinal/value correlation.
- Preserve category semantic/history evidence; quarantine contradictory type,
  system key, duplicate normalized name, missing parent or invalid allocation
  rather than silently repairing financial meaning.
- Convert vendor strings into rows through a versioned normalization policy;
  preserve original display values and reference snapshots.
- Reset template checklist completion state in target definitions while
  retaining source values as migration evidence; existing Spaces are not
  rewritten from templates.
- Seed capability defaults from active trusted Owner/Admin/Employee membership
  and financial-access records, then reconcile every grant explicitly. Do not
  infer authority from observed historical writes.

Reconcile source/target definitions, IDs, normalized names, system keys,
semantic types, archives, order, Project allocations/cents, template/checklist
content, vendor mappings, personal ownership, visibility results and every
quarantine reason.

## Required Acceptance Tests

### Authorization and domain behavior

- Owner/Admin/default Employee and each delegated capability pass exactly the
  matrix above;
- financial limited/none members cannot read, count, search, sync, allocate or
  mutate hidden revenue categories;
- system category mutation fails for every app/MCP role and direct table access;
- in-use category delete fails; archive preserves historical resolution;
- semantic change routes to typed correction and cannot use ordinary edit;
- complete Project category configuration and each reorder commit atomically or
  not at all under concurrent writes;
- applying a template resets completion and later template edits do not change
  existing Spaces; and
- concurrent vendor suggestions normalize to one stable row while historical
  evidence retains its captured value.

### Offline, RLS, and migration

- offline create/edit/reorder survives restart and resolves stale revisions
  without silent partial order;
- revoked capability fails on reconnect even when cached UI still shows action;
- cross-account, forged role/capability, other-Principal preference and service-
  identity bypass attempts fail without existence leakage;
- RLS, Sync Stream, app and MCP results match for the complete role/financial/
  delegated-capability matrix;
- duplicate/malformed/system-conflict migration fixtures quarantine
  deterministically and repeated import is idempotent; and
- target counts/order/allocations/visibility reconcile without copying broad
  Firebase member-write permissions.

## Approval Consequences

If approved:

1. update the canonical roles/reference/project/category/template specs and add
   the confirmed product decision;
2. promote the matrix and typed contracts into architecture 04/05/06;
3. remap the 19 O-026 surfaces, retaining any other blockers;
4. design reviewed schema, RLS/Sync profiles, operation handlers and migration
   fixtures; and
5. prove role/financial/capability parity and offline conflict behavior in the
   vertical spike.

## Approval Checklist

- [ ] Owner/Admin manage ordinary categories; financial configuration is a named
  capability and system categories remain server-only.
- [ ] Project allocations require `manage_project_budgets` plus visibility.
- [ ] Template management is Owner/Admin by default and explicitly delegable.
- [ ] Authorized capture may suggest a vendor; only administrators manage the
  shared list.
- [ ] Employee reads are visibility-safe; financial access remains distinct from
  role.
- [ ] Personal preferences remain own-Principal only.
- [ ] Archive/merge/correction replace unsafe delete/rename semantics.
- [ ] Reorder and complete Project configuration are atomic and revision-safe.
