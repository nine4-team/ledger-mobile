# Prompt Pack — Chat C: Transaction Screens

## Goal

Remove all `await`ed Firestore writes from transaction screens. After Chat A, `createTransaction` returns a `string` synchronously. All `updateTransaction` / `deleteTransaction` calls become fire-and-forget with `.catch()`.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **Keep `await` on reads** when data drives subsequent logic — use cache-first mode (`'offline'`).
3. **Keep `await` on `saveLocalMedia` / `deleteLocalMediaByUrl`** — local SQLite ops, not Firestore.
4. **Remove `isSubmitting` state** where it gates on Firestore write completion. Navigate immediately.

## Prerequisite

Chat A must be complete — `createTransaction()` now returns `string` (not `Promise<string>`).

## File: `app/transactions/[id]/index.tsx`

Remove `await` + add `.catch()`:

| Operation | Notes |
|-----------|-------|
| Receipt image handlers (add/remove/set primary) | ~3 instances of `updateTransaction`. Keep `await saveLocalMedia`. |
| Other image handlers (add/remove/set primary) | ~3 instances of `updateTransaction`. Keep `await saveLocalMedia`. |
| `handleRemoveLinkedItem` | `updateItem` fire-and-forget |
| `handleDelete` | `deleteTransaction` fire-and-forget + navigate immediately |

## File: `app/transactions/[id]/edit.tsx`

| Operation | Notes |
|-----------|-------|
| 6 image handler instances | `updateTransaction` fire-and-forget. Keep `await saveLocalMedia`. |
| `handleSave` (~line 236) | Fire-and-forget `updateTransaction`. Fire-and-forget `Promise.all` for linked item category updates. Remove `isSubmitting`. Navigate immediately. |

## File: `app/transactions/new.tsx`

| Operation | Notes |
|-----------|-------|
| `handleSubmit` (~line 157) | `createTransaction()` now synchronous — remove `await`. Remove `isSubmitting`. Navigate immediately. |

## Pattern Example

```typescript
// BEFORE:
const handleDelete = async () => {
  try {
    await deleteTransaction(accountId, transactionId);
    router.replace('/transactions');
  } catch (err) {
    Alert.alert('Error', 'Failed to delete');
  }
};

// AFTER:
const handleDelete = () => {
  deleteTransaction(accountId, transactionId).catch(err => {
    console.warn('[transactions] delete failed:', err);
  });
  router.replace('/transactions');
};
```

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device with airplane mode:
   - Create transaction → instant navigate, appears in list.
   - Edit transaction fields → saves instantly, navigates back.
   - Add/remove receipt and other images → UI updates immediately.
   - Delete transaction → navigates immediately, gone from list.
   - Linked item category updates apply when back online.
