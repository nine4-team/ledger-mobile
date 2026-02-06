## Goal
Ship Roles v2 **category-scoped access control** in a way that:

- is enforced server-side (Firebase Rules / server-side enforcement is source of truth)
- stays compatible with `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline persistence + scoped listeners + request-doc workflows; no “subscribe to everything”)
- preserves canonical inventory sale semantics:
  - canonical inventory sale transactions are category-coded (`transaction.budgetCategoryId` populated)
  - canonical inventory sale transactions are direction-coded (`inventorySaleDirection` populated)
  - transaction visibility is evaluated by `transaction.budgetCategoryId` (no item-join required for transaction visibility)

Spec source of truth:
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md`

Canonical attribution evidence sources (must remain consistent):
- `40_features/project-items/flows/inherited_budget_category_rules.md`
- `40_features/project-transactions/feature_spec.md`
- `40_features/budget-and-accounting/feature_spec.md`

## Primary risk (what can go wrong)
- Accidentally treating canonical system rows as editable/mutable by users (canonical rows must be system-owned).
- Client-side filtering after downloading unauthorized rows (violates the security model and the “no subscribe to everything” constraint).
- Offline DB containing out-of-scope rows (privacy + confusing UX).

## Output files (this work order will produce)
Minimum:
- `40_features/_cross_cutting/category-scoped-permissions-v2/feature_spec.md` (already exists)
- `40_features/_cross_cutting/category-scoped-permissions-v2/plan.md` (this file)
- `40_features/_cross_cutting/category-scoped-permissions-v2/prompt_packs/` (Chats A–D)

Optional (if needed by implementation complexity):
- `40_features/_cross_cutting/category-scoped-permissions-v2/acceptance_criteria.md`

## Implementation phases (2–4 slices)

### Phase A — Data shape + server-side gates (entitlements + write rules)
**Goal**: establish the membership entitlement shape and hard server-side allow/deny behavior for:
- item reads/writes (including “own uncategorized” exception)
- non-canonical transaction reads
- canonical inventory sale transaction reads (category-scoped by `transaction.budgetCategoryId`)

**Exit criteria**
- There is a single, explicit entitlement representation per member (admin flag + category set/map).
- All key allow/deny rules from the spec are enforceable without relying on UI.

### Phase B — Scoped query/listener shaping + offline cache semantics
**Goal**: ensure all reads are **scoped** and server-enforced:
- queries/listeners are shaped so out-of-scope docs can never be returned
- the UI never “downloads then filters” unauthorized data
- offline behavior matches server visibility as closely as Firestore cache semantics allow

**Exit criteria**
- Items and non-canonical transactions are queried with scope constraints (no “fetch everything then filter”).
- Canonical inventory sale transactions are queried with the same category scope constraints as non-canonical transactions.
- Documented behavior when `allowedBudgetCategoryIds` changes (queries/listeners update immediately; UI reflects new visibility set).

### Phase C — UI gating + canonical Transaction Detail redaction
**Goal**: ensure consistent UX:
- category pickers/filters show only allowed categories
- canonical transaction detail shows only in-scope linked items

**Exit criteria**
- No UI shows out-of-scope categories.
- Canonical Transaction Detail never leaks out-of-scope items.

### Phase D — Hardening (tests + edge-case audit)
**Goal**: reduce regression risk and validate invariants.

**Exit criteria**
- Tests cover the core read/write matrix (admin vs scoped, null vs non-null item category, canonical vs non-canonical transaction).
- Tests cover canonical system-row rules: canonical inventory sale rows are system-owned/read-only and category-scoped by `transaction.budgetCategoryId`.

## Prompt packs (copy/paste)
Create `prompt_packs/` with one chat per phase:
- Chat A: server-side rules + membership entitlement shape
- Chat B: scoped queries/listeners + offline cache semantics
- Chat C: UI gating + canonical Transaction Detail redaction behavior
- Chat D: tests + edge-case audit

