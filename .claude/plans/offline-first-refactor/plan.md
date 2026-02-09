# Offline-First Architecture Refactor

## Problem

Space edit screens hang indefinitely on "Saving..." because they `await` Firestore server acknowledgment before navigating. The same anti-pattern exists throughout the entire app — 65+ awaited Firestore writes across 15+ files.

The app's architecture docs (`.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`) and `CLAUDE.md` are explicit:

- **Principle 1:** A mutation is "done" for the user when it is accepted locally by Firestore (even if not yet synced).
- **Invariant A:** No "spinners of doom" — show data immediately, never block UI.
- **Invariant B:** create/update/delete works locally (queued writes).

**Root cause:** No project-level CLAUDE.md encoded these rules when features were first built, so AI devs followed default `await` patterns. The `createProject` Cloud Function set a precedent that "creating things needs server acknowledgment."

## Reference Pattern (already applied to space edits)

```typescript
// Fire-and-forget: no await, .catch() for error logging
updateSpace(accountId, spaceId, { name, notes }).catch(err => {
  console.warn('[spaces] update failed:', err);
});
router.replace(backTarget); // Navigate immediately
```

## True Exceptions (keep awaited)

- **Firebase Storage byte uploads** (`enqueueUpload`, `processUploadQueue`, `uploadBusinessLogo`) — requires network. But the Firestore metadata write after upload should be fire-and-forget.
- **Firebase Auth** (`user.updateProfile()`, `auth.currentUser.reload()`) — requires network.
- **Multi-doc server transactions** (`createAccountWithOwner`, `createInvite`, `acceptInvite`) — need server-side atomicity.
- **Read operations** — must stay awaited when returned data drives subsequent logic, but must use cache-first mode (`'offline'`), not server-first.

## Execution Order

```
Chat A (Service Layer)  ── must complete first ──┐
                                                  ├── Chats B-G (all in parallel)
                                                  │    ├── Chat B: Item Screens
                                                  │    ├── Chat C: Transaction Screens
                                                  │    ├── Chat D: Space Screens
                                                  │    ├── Chat E: Project Screens
                                                  │    ├── Chat F: Settings & Budget
                                                  │    └── Chat G: Shared Components + Request-Doc Flows
                                                  │
```

Chat A **must** land and be committed before starting B-G, because B-G depend on the service layer signature changes (sync return types, `addDoc` → `setDoc`).

## Prompt Packs

Each file in `prompt_packs/` is a self-contained, copy-paste-ready prompt for an AI dev chat:

| File | Scope | Depends on |
|------|-------|------------|
| `chat_a_service_layer.md` | Service function signatures, `addDoc` → `setDoc`, missing `trackPendingWrite`, cache-first reads | Nothing |
| `chat_b_item_screens.md` | `app/items/` screens | Chat A |
| `chat_c_transaction_screens.md` | `app/transactions/` screens | Chat A |
| `chat_d_space_screens.md` | `app/*/spaces/` + `SpaceSelector` | Chat A |
| `chat_e_project_screens.md` | `app/project/`, `ProjectShell` | Chat A |
| `chat_f_settings_and_budget.md` | `app/(tabs)/settings.tsx`, `BudgetCategoryManagement` | Chat A |
| `chat_g_shared_and_request_docs.md` | `SharedItemsList`, `inventoryOperations`, `resolveItemMove` | Chat A |

## Verification (after all chats complete)

1. `npx tsc --noEmit` — no TypeScript errors from signature changes.
2. Manual test each flow on device with airplane mode toggled:
   - Create/edit/delete items, transactions, spaces, projects
   - Toggle bookmarks, manage images
   - Budget category CRUD, vendor management
   - Cross-project item moves (request-doc flows)
3. Verify sync status indicator updates correctly (via `trackPendingWrite`).
4. Confirm `onSnapshot` listeners reflect changes instantly in the UI.
5. Confirm no "Saving..." spinners remain — all operations feel instant.
