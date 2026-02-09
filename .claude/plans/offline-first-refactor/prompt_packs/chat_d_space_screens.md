# Prompt Pack — Chat D: Space Screens

## Goal

Remove all `await`ed Firestore writes from space detail screens and the `SpaceSelector` component. After Chat A, `createSpace` and `createSpaceTemplate` return synchronously.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **Keep `await` on `saveLocalMedia` / `deleteLocalMediaByUrl`** — local SQLite ops, not Firestore.
3. **Remove `isSubmitting` / `isCreating` state** where it gates on Firestore write completion.

## Prerequisite

Chat A must be complete — `createSpace()` and `createSpaceTemplate()` now return `string` (not `Promise<string>`).

## File: `app/business-inventory/spaces/[spaceId].tsx`

| Operation | Notes |
|-----------|-------|
| `handleSaveChecklists` | `updateSpace` fire-and-forget |
| Image handlers (add/remove/set primary) | `updateSpace` fire-and-forget. Keep `await saveLocalMedia`. |
| Item move handlers | `updateItem` fire-and-forget for same-project moves |
| `handleDelete` | `deleteSpace` fire-and-forget + navigate immediately |
| `handleSaveTemplate` | `createSpaceTemplate` now synchronous — no `await` needed. Fire-and-forget. |

## File: `app/project/[projectId]/spaces/[spaceId].tsx`

Mirror of business-inventory space screen — apply identical changes:

| Operation | Notes |
|-----------|-------|
| `handleSaveChecklists` | `updateSpace` fire-and-forget |
| Image handlers (add/remove/set primary) | `updateSpace` fire-and-forget. Keep `await saveLocalMedia`. |
| Item move handlers | `updateItem` fire-and-forget for same-project moves |
| `handleDelete` | `deleteSpace` fire-and-forget + navigate immediately |
| `handleSaveTemplate` | `createSpaceTemplate` now synchronous — fire-and-forget |

## File: `src/components/SpaceSelector.tsx`

| Operation | Notes |
|-----------|-------|
| `handleCreateSpace` (~line 135) | `createSpace()` now synchronous — remove `await`. Remove `isCreating` state. Call `onChange(newSpaceId)` immediately. |

## Pattern Example

```typescript
// BEFORE:
const handleSaveChecklists = async () => {
  setIsSaving(true);
  try {
    await updateSpace(accountId, spaceId, { checklists });
  } catch (err) {
    Alert.alert('Error', 'Failed to save');
  } finally {
    setIsSaving(false);
  }
};

// AFTER:
const handleSaveChecklists = () => {
  updateSpace(accountId, spaceId, { checklists }).catch(err => {
    console.warn('[spaces] update checklists failed:', err);
  });
};
```

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device with airplane mode:
   - Save checklists → instant, no spinner.
   - Add/remove images → UI updates immediately.
   - Delete space → navigates immediately, space gone from list.
   - Create space from template → instant, appears in list.
   - `SpaceSelector` create → inline space creation is instant.
