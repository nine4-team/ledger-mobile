# Prompt Pack — Chat E: Project Screens

## Goal

Remove all `await`ed Firestore writes from project screens. After Chat A, `createProject` returns synchronously (refactored from Cloud Function to client-side). All `updateProject` / `deleteProject` / `updateProjectPreferences` calls become fire-and-forget.

## Required Reading

- Architecture: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`
- Rules: `CLAUDE.md` § Offline-First Coding Rules

## Rules (non-negotiable)

1. **Never `await` Firestore write operations.** Fire-and-forget with `.catch()`.
2. **Keep `await` on Firebase Storage uploads** (`uploadBusinessLogo`, image uploads) — byte uploads require connectivity.
3. **Remove `isSubmitting` state** where it gates on Firestore write completion. Navigate immediately.
4. **Remove `isOnline` guards** that block creation — offline Firestore writes are now supported.

## Prerequisite

Chat A must be complete — `createProject()` now returns `{ projectId: string }` synchronously (not via Cloud Function).

## File: `src/screens/ProjectShell.tsx`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~203 | `handleDelete` | `deleteProject` fire-and-forget + navigate immediately |
| ~219 | `handlePinToggle` | `updateProjectPreferences` fire-and-forget |

## File: `app/project/[projectId]/edit.tsx`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~153 | `updateProject` (basic fields) | Fire-and-forget |
| ~171/174 | `updateProject` (mainImageUrl) | Fire-and-forget (the image upload above stays awaited) |
| ~185 | `Promise.allSettled(budgetPromises)` | Fire-and-forget |
| — | `isSubmitting` | Remove. Navigate immediately. |

## File: `app/project/new.tsx`

| Approx Line | Operation | Notes |
|-------------|-----------|-------|
| ~99 | `isOnline` guard | **Remove entirely** — offline creates now work |
| — | `createProject()` | Now synchronous — remove `await`. Remove `isSubmitting`. |
| ~135 | `updateProject(mainImageUrl)` | Fire-and-forget (upload stays awaited) |
| ~152 | `Promise.allSettled(budgetPromises)` | Fire-and-forget |
| — | Navigation | Navigate immediately after firing all writes |

## Pattern Example

```typescript
// BEFORE:
const handleSubmit = async () => {
  if (!isOnline) {
    Alert.alert('Offline', 'You must be online to create a project.');
    return;
  }
  setIsSubmitting(true);
  try {
    const { projectId } = await createProject({ name, ... });
    if (mainImage) {
      const url = await uploadImage(mainImage);
      await updateProject(accountId, projectId, { mainImageUrl: url });
    }
    router.replace(`/project/${projectId}`);
  } catch (err) {
    Alert.alert('Error', 'Failed to create project');
  } finally {
    setIsSubmitting(false);
  }
};

// AFTER:
const handleSubmit = async () => {
  const { projectId } = createProject({ name, ... });

  if (mainImage) {
    // Upload requires connectivity — keep awaited
    const url = await uploadImage(mainImage);
    updateProject(accountId, projectId, { mainImageUrl: url }).catch(err => {
      console.warn('[projects] set main image failed:', err);
    });
  }

  // Budget category assignments — fire-and-forget
  Promise.allSettled(budgetPromises).catch(err => {
    console.warn('[projects] budget setup failed:', err);
  });

  router.replace(`/project/${projectId}`);
};
```

Note: `handleSubmit` stays `async` because the image upload (Firebase Storage) still needs `await`. But Firestore writes are all fire-and-forget.

## Verification

1. `npx tsc --noEmit` — no type errors.
2. Manual test on device with airplane mode:
   - Create project without image → instant navigate, project appears in list.
   - Create project with image → navigates after upload (or shows upload-pending state), project doc created immediately.
   - Edit project fields → saves instantly, navigates back.
   - Delete project → navigates immediately, project gone from list.
   - Pin/unpin project → instant toggle.
   - No `isOnline` guard blocks project creation.
