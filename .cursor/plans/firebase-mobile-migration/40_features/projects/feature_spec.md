# Projects — Feature spec (Firebase mobile migration)

## Intent
Provide an offline-ready Projects experience: users can browse projects, open a project shell, and manage project metadata with predictable offline behavior.

Architecture baseline (mobile):
- **Firestore-native offline persistence** is the default (Firestore is canonical).
- “Freshness” while foregrounded is achieved via **scoped listeners** on bounded queries (never “listen to everything”).
- Any multi-doc/invariant operations use **request-doc workflows** (Cloud Function applies changes in a transaction).

## Owned screens / routes

### Projects list
- **Route**: `/projects` (also `/` entrypoint)
- **Web parity source**: `src/pages/Projects.tsx`

### Project shell
- **Route**: `/project/:projectId/*`
- **Tabs**: `items`, `transactions`, `spaces`, `accounting`
- **Above tabs (required container)**:
  - **Project header container**: a single container above the section tabs that includes:
    - **Project info**: basic project identity + context (e.g., name, client, optional main image, key metadata/affordances).
    - **Budget module (compact)**: a small budget progress surface (e.g., overall + pinned categories summary). This is **not** a tab.
- **Web parity source**: `src/pages/ProjectLayout.tsx`, `src/utils/routes.ts`

## Primary flows

### 1) Browse projects
- Load projects for the current account.
- Show loading → grid list → empty state.
- Tap a project → navigate to project Items tab by default (web uses `Open Project` linking to `projectItems(project.id)`).

Parity evidence:
- `src/pages/Projects.tsx` (loading/empty/grid + “Open Project” button)
- `src/utils/routes.ts` (`projectItems`, `projectsRoot`)

### 2) Create project (with optional main image)
Inputs:
- Required: `name`, `clientName`
- Optional: `description`, **project category budgets** (per-category allocations under `projects/{projectId}/budgetCategories/{budgetCategoryId}`), `main image`, `settings`

Web behavior summary:
- Create is initiated from Projects list (modal form).
- Form submission is blocked unless offline prerequisites are warm (metadata caches).
- If online, create attempts a network insert; if offline or network fails, creation is queued for offline processing and returns an optimistic project id.
- If an image was selected, for new projects it uploads after create and then patches the project with `mainImageUrl`.

Parity evidence:
- Create entrypoint + modal: `src/pages/Projects.tsx`
- Form validation + post-create image upload: `src/components/ProjectForm.tsx`
- Offline prerequisites gate: `src/hooks/useOfflinePrerequisites.ts` and `src/components/ui/OfflinePrerequisiteBanner.tsx`
- Offline queue fallback + optimistic id: `projectService.createProject` in `src/services/inventoryService.ts`

Firebase migration behavior (required delta: entitlements gating):
- **Project creation MUST be server-enforced** via a callable Function `createProject(...)` (no direct client create), per `40_features/_cross_cutting/billing-and-entitlements/feature_spec.md`.
- Function responsibilities:
  - verify membership/role for `accountId`
  - read `entitlements/current` for `accountId`
  - enforce `projectCount < maxProjects` (either via query or server-maintained counter)
  - create project doc (and any required server-owned denormalized counters/fields)
  - seed pinned budget categories for the creator (recommended):
    - create `accounts/{accountId}/users/{userId}/projectPreferences/{projectId}` with `pinnedBudgetCategoryIds = [<furnishingsCategoryId>]`
    - Source of truth: `20_data/data_contracts.md` → `ProjectPreferences`

Offline policy choice (explicit):
- **Chosen policy (intentional delta vs current web)**: *Option A* — **block over-limit creation while offline**.
  - Rationale: avoids confusing “draft projects that disappear” when entitlements deny on reconnect; matches the cross-cutting recommendation.
  - Note: this differs from current web behavior which supports offline-queued project creation.

### 3) Edit project
- Initiated from Project shell (Edit button opens ProjectForm prefilled).
- On submit: update project and refresh snapshot.
- Image behavior:
  - If editing and new image selected: upload first, then write `mainImageUrl`.

Parity evidence:
- Edit flow: `src/pages/ProjectLayout.tsx` (`isEditing`, `handleEditProject`)
- Update + offline fallback: `projectService.updateProject` in `src/services/inventoryService.ts`
- Image upload on edit: `src/components/ProjectForm.tsx`

### 4) Delete project
- Initiated from Project shell (Delete button shows confirmation dialog).
- On confirm: delete project and return to Projects list.
- If delete fails: show error toast and keep user on the screen.

Parity evidence:
- Confirmation dialog + delete flow: `src/pages/ProjectLayout.tsx` (`showDeleteConfirm`, `handleDeleteProject`)
- Delete + offline fallback: `projectService.deleteProject` in `src/services/inventoryService.ts`

### 5) Refresh project snapshot
- Project shell provides a refresh affordance.
- Refresh re-fetches at minimum: project + transactions + items + spaces.
  - Mobile uses Firestore reads with a server preference when online (cache is the fallback), per `OFFLINE_FIRST_V2_SPEC.md`.
- If refresh fails: show user-facing error and allow retry.

Parity evidence:
- Refresh button + behavior: `src/pages/ProjectLayout.tsx` (`handleRefreshProject`, `refreshCollections({ includeProject: true })`)
- Snapshot lifecycle + reconnect refresh: `src/contexts/ProjectRealtimeContext.tsx`

## Offline-first behavior (mobile target)

### Local source of truth
- UI reads from **Firestore’s local cache** via the native Firestore SDK (cache-first reads with server reconciliation when online).
- Writes are **direct Firestore writes** (queued offline by Firestore-native persistence).
- SQLite is **not** a source of truth here; it is only permitted as an **optional derived search index** module (see `OFFLINE_FIRST_V2_SPEC.md`) when robust offline multi-field search is required.

Canonical architecture reference:
- `OFFLINE_FIRST_V2_SPEC.md` (Firestore-native offline + scoped listeners + request-doc workflows; no bespoke outbox/delta-sync engine).

### Restart behavior
- On cold start:
  - Projects list should render from local cache if present (avoid empty flash).
  - Project shell should hydrate cached snapshot (project + items/transactions/spaces) if available.

Parity evidence (web hydration):
- `hydrateProjectsListCache`, `hydrateProjectCache` in `src/utils/hydrationHelpers.ts`
- Project offline hydrate path: `src/contexts/ProjectRealtimeContext.tsx` (`hydrateProjectFromIndexedDB` when offline)

### Reconnect behavior
- When returning online, active project shells should refresh collections and clear any “hydrated from cache” stale indicator.

Parity evidence:
- `src/contexts/ProjectRealtimeContext.tsx` (offline→online transition triggers refresh of active projects)
- Web-only: additional refresh after outbox flush: `onSyncEvent('complete', ...)` in `src/contexts/ProjectRealtimeContext.tsx`

## Collaboration / “realtime” expectations (mobile target)
- **Scoped listeners only (never unbounded)**:
  - Projects list: attach a listener to the bounded projects query for `currentAccountId`.
  - Project shell: attach a listener to the project doc, plus listeners for the currently visible tab’s bounded query (items/transactions/spaces) as needed.
  - Detach listeners on background; reattach on resume.
- **Cost control** is achieved through scoping (bounded queries, pagination/limits), not a bespoke delta-sync engine.

Intentional delta vs current web:
- Web uses a custom local-first + realtime strategy (Supabase/IndexedDB/outbox-style patterns). Mobile uses **Firestore-native offline + scoped listeners** per `OFFLINE_FIRST_V2_SPEC.md`.

## Permissions and gating

### Authentication + account context
- User must be authenticated and have an active `accountId` to list/open/manage projects.

Parity evidence:
- Projects list requires `currentAccountId` and shows a “No Account Selected” guard UI: `src/pages/Projects.tsx`
- Account derivation and offline fallback: `src/contexts/AccountContext.tsx`

### Role gating (coarse v1)
Terminology mapping:
- Web roles: `owner | admin | user` (`user` ≈ “member”).

Firebase migration requirement:
- Callable `createProject` must verify membership + role (see entitlements doc).

Policy note:
- The current web Projects screens do not enforce role gating client-side; treat mobile role gating as **server-enforced** first (Rules/Functions), with optional client UX gates as follow-up.

### Offline prerequisites (metadata caches)
- Project form submission is blocked unless required caches are warm:
  - budget categories
  - vendor defaults

Parity evidence:
- `src/hooks/useOfflinePrerequisites.ts` and `useOfflinePrerequisiteGate` usage in `src/components/ProjectForm.tsx`

