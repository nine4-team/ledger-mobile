# Issue: TransactionDetailScreen - Cannot convert undefined value to object

**Status:** Active
**Opened:** 2026-02-11
**Resolved:** _pending_

## Info
- **Symptom:** `TypeError: Cannot convert undefined value to object` when navigating to TransactionDetailScreen
- **Affected area:** `app/transactions/[id]/index.tsx` (TransactionDetailScreen), line 281
- **Introduced by:** Commit `a033136` — "feat(WP03): Migrate TransactionDetailScreen to SharedItemsList picker mode"
- **Engine-specific:** Hermes (React Native). In V8, `undefined[0]` gives "Cannot read properties of undefined" — different message but same crash.

**Background research:**

The WP03 migration (spec 006 item-list-picker-normalization) replaced `SharedItemPicker` with `SharedItemsList` in picker mode. This required adding a `useItemsManager` instance for picker state:

```typescript
// line 281-283 in index.tsx
const pickerManager = useItemsManager({
    items: activePickerItems,
});
```

`useItemsManager` requires `sortModes: S[]` and `filterModes: F[]` as mandatory config fields (`src/hooks/useItemsManager.ts` type `UseItemsManagerConfig`). The call above omits both.

Inside the hook, line 122:
```typescript
const [sortMode, setSortMode] = useState<S>(config.defaultSort ?? config.sortModes[0]);
```

- `config.defaultSort` = `undefined` (not provided) → triggers `??` fallback
- `config.sortModes` = `undefined` (not provided)
- `config.sortModes[0]` → Hermes calls `ToObject(undefined)` → **throws**

This runs on EVERY render because JavaScript evaluates `useState()` arguments before calling the function. Line 124 also accesses `config.sortModes[0]` as a plain assignment.

**Note:** This is NOT the same issue as the Firestore `snapshot.data()` spreading bug tracked in `space-edit-undefined-spread.md`. That was a service-layer issue; this is a component-layer missing-arguments bug.

## Experiments

### H1: pickerManager missing required sortModes/filterModes
- **Rationale:** Commit a033136 added `useItemsManager({items})` without sortModes/filterModes. The hook accesses `config.sortModes[0]` unconditionally. In Hermes, `undefined[0]` throws "Cannot convert undefined value to object".
- **Experiment:** Read useItemsManager.ts line 122 — confirm `config.sortModes[0]` is accessed unconditionally; read TransactionDetailScreen line 281 — confirm `sortModes` is missing.
- **Result:** Confirmed. `config.sortModes` is `undefined`, line 122 does `config.sortModes[0]` → Hermes throws "Cannot convert undefined value to object".
- **Verdict:** Confirmed

## Resolution
_Awaiting user verification — fix applied, reload app to test._

- **Root cause:** Commit `a033136` added `useItemsManager({items: activePickerItems})` without the required `sortModes` and `filterModes` arrays. In Hermes, `config.sortModes[0]` (where sortModes is undefined) triggers `ToObject(undefined)` → "Cannot convert undefined value to object".
- **Fix:** Added `sortModes: ['created-desc']` and `filterModes: ['all']` to the pickerManager call at line 281.
- **Files changed:** `app/transactions/[id]/index.tsx`
- **Other screens checked:** `SpaceDetailContent.tsx` pickerManager already had correct args. No other callsites affected.
- **Lessons:**
  1. Hermes error messages differ from V8 — "Cannot convert undefined value to object" in Hermes is the equivalent of "Cannot read properties of undefined" in V8. Both mean property access on undefined.
  2. TypeScript required fields don't prevent runtime crashes — `sortModes: S[]` is required in the type, but JS doesn't enforce this at runtime. The hook should defensively default: `config.sortModes?.[0] ?? 'created-desc'`.
  3. When migrating components (SharedItemPicker → SharedItemsList), all hook contract requirements must be satisfied, not just the ones used by the new component.
