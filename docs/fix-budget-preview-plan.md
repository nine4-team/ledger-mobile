# Fix: Budget Progress Bars Not Rendering on Project Cards

## Context

`BudgetProgressPreview` is already wired into `ProjectCard` and renders pinned budget category progress bars. However, **nothing shows** because of a state synchronization gap: `ensureProjectPreferences()` seeds Furnishings as a pinned category for new projects, but the result never flows back into the component state. Additionally, the function uses `'online'` reads and awaits the Firestore write, violating offline-first rules.

## Changes

### 1. `src/data/projectPreferencesService.ts` — Fix `ensureProjectPreferences`

Three issues to fix in this function (lines 57-92):

**a) Return created preferences instead of `void`**
- Change return type: `Promise<void>` → `Promise<ProjectPreferences | null>`
- Return `null` from early exits (firebase not configured, no uid, doc already exists)
- Construct and return the `ProjectPreferences` object after writing

**b) Use `'offline'` mode for reads (lines 73, 77)**
- `refreshBudgetCategories(accountId, 'online')` → `'offline'`
- `refreshProjectBudgetCategories(accountId, projectId, 'online')` → `'offline'`
- These are reads inside a save path — must use cache-first per offline-first rules

**c) Fire-and-forget the `setDoc` (line 82)**
- Remove `await` from `setDoc(ref, ...)`
- Add `.catch(err => console.error(...))` for error logging
- Keep `trackPendingWrite()` after the write call

### 2. `app/(tabs)/index.tsx` — Optimistically update state after seeding (lines 136-147)

Replace the fire-and-forget `void ensureProjectPreferences(...)` calls with a pattern that merges the returned preferences into state:

```typescript
fetchProjectPreferencesMap({ accountId, userId, projectIds })
  .then(async (prefs) => {
    setProjectPreferences(prefs);

    const missingIds = projectIds.filter((id) => !prefs[id]);
    if (missingIds.length === 0) return;

    const results = await Promise.all(
      missingIds.map((id) =>
        ensureProjectPreferences(accountId, id).catch(() => null)
      )
    );

    const seeded: Record<string, ProjectPreferences> = {};
    results.forEach((r) => {
      if (r) seeded[r.projectId] = r;
    });

    if (Object.keys(seeded).length > 0) {
      setProjectPreferences((prev) => ({ ...prev, ...seeded }));
    }
  })
  .catch(() => {
    setProjectPreferences({});
  });
```

The `await Promise.all` here only waits on **cache-first reads** (to determine if Furnishings exists). The Firestore write is fire-and-forget inside `ensureProjectPreferences`. The initial `setProjectPreferences(prefs)` already renders the cards immediately; the second call is an incremental update that adds pinned categories to cards that were missing them.

### Files Modified
- `src/data/projectPreferencesService.ts` — return type, offline reads, fire-and-forget write
- `app/(tabs)/index.tsx` — consume returned preferences, merge into state

### Files NOT Modified (verified no changes needed)
- `src/components/budget/BudgetProgressPreview.tsx` — rendering logic is correct; it just wasn't getting data
- `src/components/ProjectCard.tsx` — pure pass-through, already correct

## Verification

1. Run `npx tsc --noEmit` — confirm no type errors
2. Test fresh project: create a new project with Furnishings budget enabled → project card should show Furnishings progress bar
3. Test existing project: project with saved preferences should render unchanged
4. Test offline: airplane mode → cards should still render budget bars from cache
5. Test no Furnishings: project without Furnishings → should fall back to overall budget bar (if budget > 0) or show nothing (if no budget set)
