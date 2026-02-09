# Prompt Pack — Chat G: Shared Components + Request-Doc Flows

## Goal

Remove `await`ed Firestore writes from shared components (`SharedItemsList`) and refactor request-doc inventory operation flows to work offline. After Chat A, `createRequestDoc` returns synchronously.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **`createRequestDoc` now returns synchronously** — all loops that `await` it in sequence can drop the `await`.
3. **`resolveItemMove` should be fire-and-forget from UI callers** — the `waitForScopeThenAssign` inside it subscribes via `onSnapshot` and waits for the Cloud Function to process. This continues in the background. The UI navigates immediately.

## Prerequisite

Chat A must be complete — `createRequestDoc()` now returns `string` (not `Promise<string>`).

## Part 1: `src/components/SharedItemsList.tsx`

| Operation | Approx Line | Notes |
|-----------|-------------|-------|
| `handleDeleteItem` | ~614 | `deleteItem` fire-and-forget in Alert callback |
| Bookmark toggle | ~870, ~911 | `updateItem` fire-and-forget |

## Part 2: `src/data/inventoryOperations.ts`

All three functions loop through items and `await createRequestDoc` sequentially. After Chat A refactor, `createRequestDoc` returns synchronously — remove all `await`s:

| Function | Approx Line | Change |
|----------|-------------|--------|
| `requestProjectToBusinessSale` | ~78 | Remove `await` from `createRequestDoc` in loop |
| `requestBusinessToProjectPurchase` | ~103 | Remove `await` from `createRequestDoc` in loop |
| `requestProjectToProjectMove` | ~141 | Remove `await` from `createRequestDoc` in loop |

These functions can potentially become synchronous themselves (drop `async`), or stay `async` if other awaited operations remain. Check each function body.

## Part 3: `src/data/resolveItemMove.ts`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~65 | `await updateItem` (same-project moves) | Fire-and-forget |
| ~80, ~102, ~132 | `await` request operations | Now synchronous after Chat A refactor — remove `await` |
| ~88, ~117, ~149 | `await waitForScopeThenAssign` | This subscribes via `onSnapshot` and waits for the Cloud Function to process. **Make `resolveItemMove` fire-and-forget from UI callers**; `waitForScopeThenAssign` continues in the background. |

### UI Callers of `resolveItemMove`

In both space detail screens, `resolveItemMove` calls should be fire-and-forget with `.catch()`:

- `app/business-inventory/spaces/[spaceId].tsx` — item move handlers
- `app/project/[projectId]/spaces/[spaceId].tsx` — item move handlers

**Important:** These callers are also covered by Chat D (Space Screens). If Chat D runs first, it may have already made these fire-and-forget. If not, apply here. Coordinate to avoid conflicts — the key point is that `resolveItemMove(...)` in UI code must not be awaited.

## Pattern Example

```typescript
// BEFORE (inventoryOperations.ts):
export async function requestProjectToBusinessSale(
  accountId: string,
  items: Item[],
  projectId: string
) {
  for (const item of items) {
    await createRequestDoc(accountId, {
      type: 'project-to-business',
      itemId: item.id,
      fromProjectId: projectId,
    });
  }
}

// AFTER:
export function requestProjectToBusinessSale(
  accountId: string,
  items: Item[],
  projectId: string
) {
  for (const item of items) {
    createRequestDoc(accountId, {
      type: 'project-to-business',
      itemId: item.id,
      fromProjectId: projectId,
    });
  }
}
```

```typescript
// BEFORE (UI caller):
const handleMoveItems = async () => {
  setIsMoving(true);
  try {
    await resolveItemMove(accountId, items, targetProject);
    router.back();
  } catch (err) {
    Alert.alert('Error', 'Move failed');
  } finally {
    setIsMoving(false);
  }
};

// AFTER (UI caller):
const handleMoveItems = () => {
  resolveItemMove(accountId, items, targetProject).catch(err => {
    console.warn('[inventory] move failed:', err);
  });
  router.back();
};
```

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device:
   - Delete item from shared list → instant removal from UI.
   - Toggle bookmark in shared list → instant.
   - Move items between projects → UI navigates immediately, move completes in background.
   - Move items within same project → instant (no Cloud Function needed).
   - With airplane mode: request docs queue locally, process when back online.
3. Verify `trackPendingWrite` fires for all request doc creates (covered by Chat A).
