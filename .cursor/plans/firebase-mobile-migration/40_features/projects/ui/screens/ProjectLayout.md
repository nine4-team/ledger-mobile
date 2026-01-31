# Screen contract: ProjectLayout

## Intent
Provide the per-project “workspace shell” that:
- loads a coherent snapshot (project + core collections),
- offers refresh/edit/delete affordances,
- hosts navigation to the project’s major sections (Items, Transactions, Spaces, Budget),
- behaves predictably offline and after reconnect.

## Inputs
- **Route params**:
  - `projectId` (required)
- **Query params**:
  - `budgetTab` (web supports `budget` vs `accounting`)
- **Entry points**:
  - From Projects list “Open Project”
  - Deep links into a specific tab

Parity evidence: `src/App.tsx`, `src/pages/ProjectLayout.tsx`.

## Reads (local-first)
- **Project snapshot**:
  - project doc
  - transactions list
  - items list
  - spaces list
- **Hydration**:
  - before rendering, attempt to hydrate from local cache to avoid empty flashes.

Parity evidence:
- Hydrate project cache: `src/pages/ProjectLayout.tsx` (`hydrateProjectCache`) + `src/utils/hydrationHelpers.ts`
- Snapshot provider: `src/contexts/ProjectRealtimeContext.tsx` (`useProjectRealtime`)

## Writes (local-first)
### Refresh project snapshot
- Local DB: no direct mutation besides updating local last-seen sync state.
- Request-doc: none (refresh is a read).
- Refresh re-runs the relevant Firestore reads with a server preference when online (cache remains the fallback via Firestore-native offline persistence).

Parity evidence:
- `src/pages/ProjectLayout.tsx` (`handleRefreshProject` calling `refreshCollections({ includeProject: true })`)
- `src/contexts/ProjectRealtimeContext.tsx` (`refreshCollections`, `fetchAndStore*`)

### Edit project
- Direct write to the project doc when this is a single-doc update (Firestore queues offline writes automatically).
- If an edit requires invariants/multi-doc updates (rare for Projects), use a **request-doc workflow** per `OFFLINE_FIRST_V2_SPEC.md`.

Parity evidence (web):
- `src/pages/ProjectLayout.tsx` (`handleEditProject`)
- `projectService.updateProject` in `src/services/inventoryService.ts` (offline queue fallback)

### Delete project
- If delete is “project doc only”, client can write directly (queued offline).
- If delete implies **cascades** (removing/archiving subcollections, rollups, counters, or other invariants), it must be a **request-doc workflow** so the server can apply changes atomically.

Parity evidence (web):
- `src/pages/ProjectLayout.tsx` (`handleDeleteProject`)
- `projectService.deleteProject` in `src/services/inventoryService.ts` (offline queue fallback)

## UI structure (high level)
- Header strip:
  - Back link
  - Refresh button (spins/disabled while in-flight)
  - Edit button
  - Delete button (opens confirm dialog)
  - Optional “Retry Sync” affordance when background sync error exists
- Project card:
  - optional main image
  - name + client name
  - budget tabs: Budget / Accounting (web)
  - reports entrypoints (web)
- Section tabs:
  - Items / Transactions / Spaces / Budget
  - Outlet for nested screens

Parity evidence: `src/pages/ProjectLayout.tsx`.

## User actions → behavior (the contract)
- **Open project shell**
  - If `projectId` missing: redirect back to Projects list.
  - Hydrate cached project snapshot if available.
  - If offline: show cached snapshot (if any) and avoid infinite “retry loops”.
  - If online: load snapshot and begin foreground freshness mechanism.
- **Tap refresh**
  - Re-run snapshot refresh (project + key collections).
  - If refresh fails, show a user-facing error and allow retry.
- **Tap edit**
  - Open ProjectForm with current project values.
  - Submit applies local-first update and then syncs.
  - On success, modal closes and snapshot converges.
- **Tap delete**
  - Show confirm dialog with irreversible warning.
  - Confirm triggers delete and returns to Projects list.
- **Switch section tab**
  - Navigate to the corresponding nested route.
  - Persist last active section per project (web stores section selection).

Parity evidence:
- Missing id redirect: `src/pages/ProjectLayout.tsx`
- Offline-aware load + hydrate: `src/contexts/ProjectRealtimeContext.tsx`
- Section persistence: `src/pages/ProjectLayout.tsx` + `src/utils/projectSectionStorage`

## States
- **Loading**: show “Loading project...”.
  - Observed in `src/pages/ProjectLayout.tsx`.
- **Error**:
  - If offline: show “Offline” messaging and auto-recover on reconnect.
  - If online error: show retry UI.
  - Observed in `src/pages/ProjectLayout.tsx` (offline detection + “Try Again”).
- **Not found**: show “Project not found” and allow navigation back.
  - Observed in `src/pages/ProjectLayout.tsx`.
- **Offline**:
  - If cached snapshot exists, render it.
  - If cache is cold, show offline messaging rather than implying deletion.
  - On reconnect: automatically refresh and converge.
  - Observed in `src/contexts/ProjectRealtimeContext.tsx` (offline hydrate + reconnect refresh).
- **Pending sync**:
  - Edits/deletes should show pending state in UI (badge/disabled destructive actions, as appropriate).
  - Pending clears when Firestore has committed the write (i.e., the mutated doc is no longer `hasPendingWrites`) and the server-confirmed state is visible via the normal scoped reads/listeners.
  - If an action is implemented as a **request-doc workflow** (multi-doc correctness), “pending” is tied to the request-doc lifecycle: `pending → applied` (clear) or `failed` (show error + retry).
- **Permissions denied**:
  - If membership/role denies access, show an access denied screen and prevent data leakage.
  - (Server-enforced on Firebase; client UX optional.)

## Collaboration / realtime expectations (Firebase target)
- While foregrounded on a project:
  - Use **scoped listeners** only (never unbounded).
  - Attach a listener to the project doc.
  - Attach listeners for the currently visible tab’s bounded query (items/transactions/spaces) as needed.
  - Detach listeners on background; reattach on resume.

Source: `OFFLINE_FIRST_V2_SPEC.md`.

Intentional delta vs web:
- Web uses Supabase realtime + a custom local-first layer; mobile uses **Firestore-native offline + scoped listeners**.

## Performance notes
- Refresh should be debounced/coalesced (avoid spamming server reads/refreshes).
- Nested tabs should avoid attaching unbounded listeners or loading unbounded lists; use pagination/limits and rely on Firestore cache for fast tab switches.

## Parity evidence
- `src/pages/ProjectLayout.tsx` (refresh/edit/delete, states, tab structure)
- `src/contexts/ProjectRealtimeContext.tsx` (offline hydrate, reconnect refresh, snapshot refresh)
- `src/utils/hydrationHelpers.ts` (`hydrateProjectCache`)

