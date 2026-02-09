# Ledger Mobile

## Code Conventions

### Offline-First Coding Rules

Architecture spec: `.cursor/plans/firebase-mobile-migration/10_architecture/offline_first_principles.md`

These rules are non-negotiable. Violating them causes the app to hang when connectivity is poor.

1. **Never `await` Firestore write operations in UI code.** Use fire-and-forget with `.catch()` for error logging. Navigation and UI state updates happen immediately.
2. **All `create*` service functions must return document IDs synchronously** using pre-generated IDs via `doc(collection(...))`, not `addDoc`.
3. **Read operations in save/submit handlers must use cache-first mode** (`mode: 'offline'`). Server-first reads (`mode: 'online'`) are only for explicit pull-to-refresh.
4. **No "spinners of doom"** — never show loading states that block on server acknowledgment. If local data exists, show it immediately.
5. **Only actual byte uploads (Firebase Storage) and Firebase Auth operations may require connectivity.** All Firestore writes (including request-doc creation) must work offline.
6. **All Firestore write service functions must call `trackPendingWrite()`** after the write for sync status visibility.
