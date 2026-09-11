# Decision Packet — O-038 Inventory Destination Planning

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-02
Owners: Business Inventory, Item Placement, Invoicing, Migration
Unlocks: 5 residual surfaces
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

## Decision Requested

Decide whether Ledger retains the shipped ability to remember that inventory is
intended for a Project. If retained, approve its granularity, destination data,
lifecycle, offline behavior, and migration treatment.

This packet is a product/architecture proposal. It is not product authority,
DDL, implementation, provider approval, production migration, or cutover
authorization.

## Why This Decision Is Open

The shipped Firebase feature stores one `intendedProjectId`, optional
`intendedBudgetCategoryId`, and independent resolution timestamp on an entire
Inventory Purchase. It can list, set, change, clear, resolve, and reopen that
state.

That source behavior cannot be copied into the target without a decision:

- the shipped spec explicitly limits itself to current behavior and migration
  discovery;
- no confirmed D-001–D-027 decision preserves Inventory planning;
- D-013 makes every target Project Item charge/credit Furnishings, so a legacy
  intended category cannot become Item-charge category authority;
- one Purchase may contain Items that later follow different destinations in
  the one-Item lifecycle; and
- clear, cancel, resolve, fulfill, and reopen are different user stories even
  though the current generic tool can combine them.

## Confirmed Constraints

- Inventory Purchases record real 1584 money and remain Business-Inventory
  scoped.
- Moving an Inventory Item into a Project is a separate placement/billing
  operation and creates no pre-collection Project Transaction.
- Project Item charges and credits are Furnishings under D-013.
- One physical Item identity survives acquisition, placement, return, and
  resale cycles.
- Planning metadata cannot authorize or create money, acquisition, placement,
  Link, occurrence, Invoice, reimbursement, charge, credit, or budget effects.
- Raw source Project/category/resolution values must remain correlated and
  auditable through migration even if the target feature is retired.
- App and MCP use one typed target behavior; neither receives a generic field
  patch or privileged bypass.

## Options

### Option A — Retire destination planning

Import source intent only as read-only migration evidence or a review note.
Users organize Inventory through ordinary search/notes until actual placement.

Advantages: smallest target and no competing lifecycle. Cost: removes a shipped
workflow that reminds users which Inventory is reserved for upcoming Projects.

### Option B — Preserve one destination on the whole Purchase

Keep one optional intended Project for the acquisition aggregate. Remove target
category selection because Furnishings is authoritative. Define explicit active,
canceled, and fulfilled states.

Advantages: closest to the shipped workflow and works before Items are entered.
Cost: one Purchase cannot honestly plan Items for different Projects without
splitting or overriding the aggregate.

### Option C — Item-level Project planning with a Purchase default (recommended)

An Inventory Purchase may carry a non-authoritative Project default while Items
are being captured. Each stable Item may then have its own active destination
plan. The default seeds new Item plans but does not constrain later splits and
does not itself create placement or billing.

Plans contain Project identity only. Furnishings is derived when actual
placement creates an Item charge; no intended budget category survives as
target authority.

## Recommended Lifecycle

If Option C is approved:

- `SetInventoryItemDestinationPlan` creates or revises one active plan for an
  Inventory Item under expected Item/plan revision.
- `CancelInventoryItemDestinationPlan` records explicit user cancellation; it
  does not erase history or imply placement.
- `PlaceInventoryItemInProject` fulfills the matching active plan as part of
  the authoritative placement transaction. Fulfillment is derived from the
  real operation, not a standalone manual “resolved” toggle.
- Placing the Item in another Project leaves an explicit superseded/mismatched
  plan result rather than silently rewriting history.
- A later plan is a new revision linked to the prior canceled, fulfilled, or
  superseded plan; “reopen” is not a mutable timestamp toggle.
- A Purchase-level default may be set/changed/cleared only as capture guidance.
  It has no completion, money, category, or placement authority.

## Domain and Schema Consequences

Conceptually separate:

| Family | Responsibility |
|---|---|
| Inventory Purchase | Real 1584 acquisition money and immutable Item membership evidence |
| Purchase planning default | Optional capture-time Project suggestion, revision and audit |
| Item destination plan | Stable Item/Project identity, lifecycle, revision and operation links |
| Item placement/occurrence | Actual current Project and billable Furnishings effect |
| Migration evidence | Raw source Purchase-level Project/category/resolution fields and anomaly state |

Use stable client-generated IDs, immutable Account ownership, foreign keys,
`timestamptz`, monotonic revisions, append-only lifecycle evidence, and indexed
Account/Item/Project/active-state lookups. Do not put target planning columns on
the money Transaction if that would make them accounting fields or prevent
split Item destinations.

## Command and Query Contract

The enabled command/query names depend on the approved option. Under the
recommendation:

- one bounded Inventory planning query returns visible active/canceled/
  fulfilled/superseded Item plans, exact revisions, Project resolver state,
  readiness, and related pending operation results;
- set/cancel commands bind Operation, Account, actor, Item, expected Item/plan
  revision, and stable Project ID;
- actual fulfillment is emitted only by the placement operation that creates
  authoritative placement/occurrence/billing evidence; and
- no command accepts a budget category, display name, Transaction field map,
  money value, occurrence ID, Invoice mutation, or completion assertion from
  the client.

## Authorization, RLS, Offline, and Sync

- Active Account membership plus Inventory visibility and the relevant
  planning capability are required. Payload Account/Project/role is never
  authorization.
- The handler re-reads Item Inventory placement, Purchase correlation, Project
  Account/lifecycle, current plan, expected revisions, and conflicting pending
  operations in one transaction.
- Direct table mutation is unavailable where it could bypass lifecycle or
  revision checks. App and MCP call the same handlers.
- The Inventory working set includes authorized plan rows, minimal Project
  resolvers, readiness, and operation results only if the feature is approved.
- Offline set/cancel is durable, idempotent, and visibly queued. A local plan
  never claims current authorization or actual placement.
- Concurrent planning and placement serialize to one explainable result with no
  partial plan/placement/billing effect.
- Restricted users receive neither hidden Projects nor revealing counts or
  plan existence.

## Migration and Reconciliation

Always export and correlate source `intendedProjectId`,
`intendedBudgetCategoryId`, `inventoryIntentResolvedAt`, Purchase identity,
Item membership, lineage/movement evidence, Project/category lifecycle, and raw
field presence before normalization.

Under Option C:

- a valid unresolved Purchase-level Project becomes a proposed/default plan;
  stable unsold Items may receive correlated active Item plans;
- a source category is retained as source evidence but never overrides target
  Furnishings;
- resolved intent maps only when actual Item movement evidence supports
  fulfillment; otherwise retain a resolved-source review state rather than
  fabricate placement;
- partial sale, multiple destination, missing/archived Project, cross-Account,
  invalid category, empty Purchase, and conflicting lineage cases receive
  deterministic per-Purchase/per-Item outcomes or quarantine; and
- repeat/interrupted imports are idempotent and retain source-to-target
  correlation even when the chosen option retires the feature.

Reconcile counts and IDs for every source intent, resolution value, Purchase,
Item, Project, target plan/default, fulfillment link, source-only retention,
and quarantine reason.

## Required Acceptance Tests

- feature-disabled migration retains every source intent without target
  behavioral exposure;
- one Purchase with Items planned for different Projects follows the approved
  granularity without splitting or rewriting money evidence;
- target Item charges always use Furnishings regardless of a source intended
  category;
- set/change/cancel/fulfill/supersede/replan transitions are explicit,
  revision-safe, idempotent, and canonically restartable;
- clear/cancel cannot masquerade as fulfillment, and fulfillment cannot occur
  without the actual placement operation;
- planning creates no Transaction, acquisition, Link, occurrence, Invoice,
  reimbursement, charge, credit, or budget contribution;
- invalid, archived, missing, and cross-Account Project references fail without
  leaking hidden identities;
- planning/placement races commit one complete serial result;
- offline queued plans survive process/device restart and surface rejection or
  conflict without disappearing; and
- app, MCP, import, RLS, Sync, reports, and reconciliation agree on the approved
  semantics.

## Affected Residual Surfaces

- `MCPTOOL-42E5CABFC6F6` — current list/follow-up projection;
- `MCPTOOL-4FF3862CBCD5` — current set/change/clear/resolve mutation;
- `MCPMOD-D14DD1E83CFE` — combined current planning/correction module;
- `FUNCMOD-E7CB6889A620` — legacy actual/intended category fallback; and
- `SWIFT-34855F53F580` — current next-step/completeness derivation containing
  planning state.

## Approval Checklist

- [ ] Choose retire, Purchase-level, or Item-level/default planning.
- [ ] Approve whether any Purchase-level default exists before Item creation.
- [ ] Confirm that target planning carries no budget category authority.
- [ ] Approve explicit cancel/fulfill/supersede/replan lifecycle behavior.
- [ ] Approve partial/full placement and multi-Project behavior.
- [ ] Approve authorization capability and offline visibility.
- [ ] Approve source migration/quarantine rules.
- [ ] Update canonical target specs and record a new confirmed D decision.
- [ ] Update architecture, capability dossier, target mappings, tests, and
      implementation slices only after the product-authority update.

Until every checked item is approved and recorded, O-038 remains open and no
target Inventory-planning query, command, schema, RLS, Sync, app, or MCP slice
is implementation-ready.
