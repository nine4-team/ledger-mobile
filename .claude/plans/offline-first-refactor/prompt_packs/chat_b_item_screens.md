# Prompt Pack — Chat B: Item Screens

## Goal

Remove all `await`ed Firestore writes from item screens. After Chat A, `createItem` returns a `string` synchronously. All `updateItem` / `deleteItem` calls become fire-and-forget with `.catch()`. Navigation and UI state updates happen immediately.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **Keep `await` on reads** when the returned data drives subsequent logic — but reads must use cache-first mode (`'offline'`).
3. **Keep `await` on `saveLocalMedia` / `deleteLocalMediaByUrl`** — these are local SQLite operations, not Firestore.
4. **Remove `isSubmitting` state** where it gates on Firestore write completion. Navigate immediately.

## Prerequisite

Chat A must be complete — `createItem()` now returns `string` (not `Promise<string>`).

## File: `app/items/[id]/index.tsx`

Remove `await` + add `.catch()` on these `updateItem` calls:

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~150 | `updateItem` (link transaction) | Keep `await getTransaction` read above (now cache-first per Chat A Part 1D) |
| ~156 | `updateItem` (unlink transaction) | Fire-and-forget |
| ~192 | `updateItem` (add image) | Keep `await saveLocalMedia` above; fire-and-forget the Firestore write |
| ~207 | `updateItem` (remove image) | Keep `await deleteLocalMediaByUrl` above; fire-and-forget the Firestore write |
| ~216 | `updateItem` (set primary image) | Fire-and-forget |
| ~222 | `updateItem` (toggle bookmark) | Fire-and-forget |
| ~247 | `updateItem` (move to inventory correction) | Fire-and-forget |
| ~283 | `deleteItem` in Alert callback | Fire-and-forget + navigate immediately |

## File: `app/items/[id]/edit.tsx`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~114 | `updateItem` (add image) | Fire-and-forget; keep `await saveLocalMedia` |
| ~127 | `updateItem` (remove image) | Fire-and-forget |
| ~136 | `updateItem` (set primary) | Fire-and-forget |
| ~149-167 | `handleSave` → `updateItem` | Fire-and-forget. Remove `isSubmitting`. Navigate immediately. |

## File: `app/items/new.tsx`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~102 | `getTransaction` read | Now cache-first (`'offline'`) per Chat A Part 1D. Keep `await` + `try/catch`. |
| ~125-127 | `createItem()` calls in loop | `createItem()` now returns synchronously — remove `await`. Remove `isSubmitting`. Navigate immediately. |

## Pattern Example

```typescript
// BEFORE:
const handleSave = async () => {
  setIsSubmitting(true);
  try {
    await updateItem(accountId, itemId, updates);
    router.back();
  } catch (err) {
    Alert.alert('Error', 'Failed to save');
  } finally {
    setIsSubmitting(false);
  }
};

// AFTER:
const handleSave = () => {
  updateItem(accountId, itemId, updates).catch(err => {
    console.warn('[items] update failed:', err);
  });
  router.back();
};
```

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device with airplane mode:
   - Edit item fields → saves instantly, navigates back, data visible in list.
   - Add/remove/reorder images → UI updates immediately.
   - Toggle bookmark → instant.
   - Delete item → navigates immediately, item gone from list.
   - Link/unlink transaction → instant.
