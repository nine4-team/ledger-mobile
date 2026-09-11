# Decision Packet — O-040 Project Budget Pinning

Status: proposed recommendation; product decision not yet approved
Last reviewed: 2026-09-03
Owners: Project Budget, Personal Preferences, App, Offline Operations, Migration
Unlocks: target Project-budget pin presentation, mutation, persistence, Sync, RLS,
and app integration
Residual register: [generated M2 queue](../conversion/residual-decision-register.generated.md)

Affected blocker: `O-040`

Affected conversion surfaces: `RULE-684AA9BB1569`, `SWIFT-093E5E4F8D20`,
`SWIFT-B6C3B72884E1`, `SWIFT-E23DAF7A18FA`, `SWIFT-D6F4A0ED81EF`,
`TEST-04DAF7B43B47`, `TEST-3D0D949763A1`, `SWIFT-58A14BD25578`,
`MCPTOOL-55857D0737AE`, `MCPMOD-8FC7F6247E2F`, `SWIFT-1DA3D2CE9B31`,
`SWIFT-800DE43469FC`, `SWIFT-14D0C2F1019A`, `SWIFT-48DE39470AF0`,
`SWIFT-D73C92887393`, `SWIFT-E1A771F6A409`, `SWIFT-27CA6EAC7092`, and
`FUNCMOD-B42AA317B971`.

## Decision Requested

Approve, revise, or reject this policy:

> Choose whether Ledger keeps personal, per-Project budget pins in the target.
> If it does, choose the exact pin target types, ordering/replacement rules,
> missing-versus-explicit-empty meaning, category lifecycle behavior and
> cleanup policy. Separately choose what Project detail and Project cards show
> when no visible pins exist. No Furnishings default, Overall target, empty
> result, card fallback or implicit write is approved by this packet.

This is a product recommendation. It is not implementation, schema, migration,
provider, production, release, or cutover approval.

## Why a Decision Is Required

The current-product specifications and source implementation establish useful
behavior, but the target authority does not yet decide which parts survive:

- preferences are scoped by user and Project and store an ordered string array;
- `overall` is mixed into that category-ID array even though it is not a budget
  category identity;
- the budget screen automatically writes Furnishings as a first-use pin;
- deletion triggers a best-effort client cleanup write, while archived category
  IDs remain stored and are skipped from display; and
- Project cards, Project details, and calculation helpers apply related but not
  identical fallback and ordering rules.

The confirmed redesign budget spec owns paid/unpaid arithmetic, not personal
pin behavior. Current-product specs, source code, conversion dossiers, and an
already implemented provider-free command primitive cannot silently choose the
new product policy.

The following are independent product questions and remain unresolved until
the approval checklist records each answer:

- whether pinning survives at all;
- whether Overall Budget is a pin target;
- whether missing preference and explicitly stored empty differ semantically;
- whether either state displays no pinned section, a Furnishings fallback, or
  some other default on Project detail;
- whether Project cards use the same fallback, a different compact fallback,
  or no pin-derived preview; and
- whether a displayed fallback is presentation-only or becomes stored data.

The recommendation below does not silently resolve any of these subdecisions.

## Confirmed Constraints

- Pinning is presentation preference only. It cannot change category
  definitions, allocation, financial visibility, contribution arithmetic, or
  paid/unpaid totals.
- A caller-supplied Principal or path is not authorization. Trusted target
  enforcement must bind the preference row to the authenticated Principal and
  authorized Account/Project.
- The app must remain useful offline from synchronized preference and category
  evidence and must not convert incomplete local evidence into authoritative
  absence or cleanup.
- O-005 still owns pending-credit budget presentation and arithmetic; O-026
  still owns shared category mutation authority.
- Source preference documents and the magic sentinel remain migration evidence,
  not automatic target schema authority.

## Options

### Option A — Typed personal pins with explicit absence (recommended)

- Keep ordered personal Project pins.
- Model category and Overall Budget as distinct typed pin targets.
- Store a unique complete ordered list; an edit replaces the list atomically.
- Treat explicit empty as “show no personal pins” and missing preference as “no
  choice saved yet.”
- Choose one explicit missing-preference/no-visible-pin behavior for Project
  detail and one for Project cards: no pin-derived section, a presentation-only
  Furnishings fallback, or another named deterministic result. Neither a
  fallback nor card parity is implied by choosing this option.
- A presentation-only fallback never writes data. The first explicit user edit
  creates the stored row unless the approved policy says pinning is removed.
- Keep archived category targets stored but hidden. Handle removed/unmappable
  targets through trusted cleanup or explicit migration/reconciliation, never a
  best-effort view-side write.

This preserves the ability to keep the visible feature while removing sentinel
ambiguity, first-render write races, and loss of absence intent. It does not
choose the no-pin/default/card presentation subdecisions.

### Option B — Preserve current implicit-write behavior

Keep the source string array, `overall` sentinel, automatic first-view
Furnishings write, and client-side stale cleanup. This most closely matches the
current implementation but carries source coupling, offline races, and
ambiguous absence/empty behavior into the target.

### Option C — Remove personal pins

Use only a deterministic system ordering/fallback. This simplifies storage and
Sync but removes an existing user customization and should require an explicit
product decision.

## Proposed Target Contract

If Option A is approved:

- one row is keyed by immutable Account, Principal, and Project identities;
- `ProjectBudgetPinTarget` is a closed tagged value with
  `category(BudgetCategoryID)` and `overallBudget` variants;
- the list is ordered and duplicate-free across the complete typed target;
- `ReplaceProjectBudgetPins` carries the complete desired list plus explicit
  not-stored or exact-revision expected state;
- explicit empty creates or updates a stored empty choice; it is not collapsed
  into missing preference;
- missing preference and no-visible-pin rendering use only the separately
  approved Project-detail and Project-card outcomes; no fallback is assumed;
- any approved presentation-only fallback causes no persistent write;
- category existence, visibility, lifecycle, membership, expected revision,
  and actor ownership are revalidated by the trusted handler;
- archived category pins remain in the stored order but do not render while
  unavailable; restoration makes them visible in their prior order;
- a permanently removed or unmappable category target is reported and handled
  by a trusted, auditable cleanup policy; incomplete local data cannot delete it;
- Project cards and Project details consume the approved projections; whether
  their no-pin/default fallback is identical remains an explicit decision; and
- pinning never alters or recomputes canonical budget contribution values.

Choosing Option A alone does not approve a Furnishings fallback, an empty
rendering, Project-card parity or any other default. Those choices must be
recorded independently. Missing and explicit empty may remain distinct stored
states even if the approved UI renders them identically.

## Offline, Concurrency, and Authorization Consequences

- A valid offline replacement becomes one durable idempotent operation only
  after the separately gated physical local-store contract exists.
- Optimistic projection retains the exact ordered target list and expected
  revision. Rejection restores or refreshes authoritative state without losing
  the operation outcome.
- Concurrent edits cannot be silent last-write-wins; not-stored/exact-revision
  preconditions expose conflicts.
- Only the authenticated Principal may read or write their row. Account
  membership alone does not expose another member's personal preferences.
- Category financial visibility is enforced before download and again before
  authoritative apply; a pin never grants category visibility.

## Migration and Reconciliation

- Correlate source path UID to one stable Principal and quarantine mismatches.
- Convert valid category IDs to typed category targets and the exact legacy
  `overall` value to the typed Overall Budget target.
- Preserve source order and report duplicates, unknown IDs, cross-Account IDs,
  malformed sentinels, missing Projects, and ambiguous Principal mappings.
- Preserve missing document versus present empty array as distinct evidence.
- Retain archived category references; classify permanently missing references
  for reviewed cleanup instead of silently dropping them during import.
- Reconcile per Account/Principal/Project row counts, ordered target hashes,
  revisions, absence/empty distinctions, and every quarantine/cleanup outcome.
- The Firebase app and its data remain unchanged before hard cutover.

## Required Acceptance Tests

- exact Account/Principal/Project ownership and cross-user denial;
- ordered category pins plus typed Overall Budget without sentinel collision;
- missing preference, stored empty, singleton, multi-pin, reorder, and duplicate
  refusal;
- every approved missing, explicit-empty and no-visible-pin Project-detail and
  Project-card outcome, including proof that presentation-only fallback makes
  no write;
- archived, restored, permanently removed, locally unavailable, and
  visibility-restricted categories;
- offline accept/restart/replay, exact-revision conflict, rejection recovery,
  and app/MCP parity where MCP exposes the capability;
- Project card and Project detail projections use their explicitly approved
  visible order/fallback policies and never alter budget arithmetic; and
- migration fixtures for `overall`, duplicates, stale IDs, cross-user paths,
  missing versus empty, and archived references.

## Approval Consequences

If approved:

1. record the chosen policy in a canonical target-spec heading and add a
   confirmed D decision;
2. revise the provider-free preference read/update primitives where their
   provisional shape differs, especially typed Overall Budget and
   missing-versus-empty behavior;
3. prepare a new application slice only after the canonical authority exists;
4. implement schema, RLS, Sync, offline operation, projections, app behavior,
   and migration under separate evidence-gated slices; and
5. remove O-040 only from surfaces whose exact approved behavior is proven.

## Approval Checklist

- [ ] Choose A, B, or C.
- [ ] Confirm whether Overall Budget remains pinnable and, if so, is typed.
- [ ] Confirm complete replacement, uniqueness, and order semantics.
- [ ] Confirm missing preference versus explicit empty behavior.
- [ ] Confirm Project-detail behavior for missing preference, explicit empty,
      and no currently visible pins.
- [ ] Confirm Project-card behavior for those same states, independently of the
      detail-screen answer.
- [ ] Confirm whether any default/fallback is presentation-only and prove that
      rendering performs no write.
- [ ] Confirm archived/restored and permanently removed category behavior.
- [ ] Confirm exact-revision conflict handling for concurrent/offline edits.
- [ ] Confirm Project cards and Project details share one visible-pin projection.
