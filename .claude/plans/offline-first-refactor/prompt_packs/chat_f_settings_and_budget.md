# Prompt Pack — Chat F: Settings & Budget Management

## Goal

Remove all `await`ed Firestore writes from the settings screen and budget category management. After Chat A, `createBudgetCategory` returns synchronously. All update/delete/reorder operations become fire-and-forget.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **Keep `await` on `uploadBusinessLogo`** — Firebase Storage byte upload requires connectivity.
3. **Remove `isSaving` / `isSubmitting` state** where it gates on Firestore write completion.
4. **Remove `Promise.race` timeout workarounds** — these were coping with the `addDoc`-blocking-offline bug. No longer needed.

## Prerequisite

Chat A must be complete — `createBudgetCategory()` now returns `string` (not `Promise<string>`).

## File: `app/(tabs)/settings.tsx`

Fire-and-forget conversions:

| Operation | Approx Lines | Notes |
|-----------|-------------|-------|
| Budget category create | ~546-570 | `createBudgetCategory()` now synchronous. **Remove `Promise.race` timeout workaround.** |
| Budget category update | — | `updateBudgetCategory` fire-and-forget |
| Budget category delete | — | `deleteBudgetCategory` fire-and-forget |
| Budget category reorder | — | `setBudgetCategoryOrder` fire-and-forget |
| Budget category archive | — | Fire-and-forget |
| Vendor slots save | — | `replaceVendorSlots` fire-and-forget |
| Vendor slots reorder | — | Fire-and-forget |
| Template create | — | `createSpaceTemplate` now synchronous. Fire-and-forget. |
| Template update | — | Fire-and-forget |
| Template archive | — | Fire-and-forget |
| Template reorder | — | Fire-and-forget |
| Business profile save | — | `saveBusinessProfile` fire-and-forget. **Keep `await uploadBusinessLogo`.** |

## File: `src/screens/BudgetCategoryManagement.tsx`

| Operation | Notes |
|-----------|-------|
| `handleReorder` | `setBudgetCategoryOrder` fire-and-forget |
| `handleDefaultCategoryChange` | `updateAccountPresets` fire-and-forget |
| `handleArchive` / `handleUnarchive` | `setBudgetCategoryArchived` fire-and-forget |
| `handleSave` | `createBudgetCategory` (now sync) or `updateBudgetCategory` — fire-and-forget. Remove `isSaving`. |

## Pattern Example

```typescript
// BEFORE (with Promise.race timeout workaround):
const handleCreateCategory = async () => {
  setIsSaving(true);
  try {
    const id = await Promise.race([
      createBudgetCategory(accountId, { name, color }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Timeout')), 5000)
      ),
    ]);
    // use id...
  } catch (err) {
    Alert.alert('Error', 'Failed to create category');
  } finally {
    setIsSaving(false);
  }
};

// AFTER:
const handleCreateCategory = () => {
  const id = createBudgetCategory(accountId, { name, color });
  // use id immediately — it's a pre-generated Firestore doc ID
};
```

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device with airplane mode:
   - Create budget category → appears instantly in list.
   - Edit/archive/delete budget category → instant.
   - Reorder categories → instant reorder.
   - Change default category → instant.
   - Save business profile (without logo) → instant.
   - Save business profile (with logo) → waits for upload, then saves.
   - Create/edit/archive templates → instant.
   - Save vendor slots → instant.
   - No `Promise.race` timeout errors.
