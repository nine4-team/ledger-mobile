# Receipt/Image Upload UI Not Updating

**Date:** 2026-03-31
**Status:** Open — reverted all changes, root cause narrowed but not fixed

## Symptom

Adding or removing a receipt image on `TransactionDetailView` succeeds (Firestore write completes, data persists) but the UI doesn't visually reflect the change. User must navigate away and back to see updates. Reported on mobile (real device), confirmed reproducible on emulator.

## Data Flow

```
uploadReceiptImage() → builds new [AttachmentRef] array
  → updateTransaction(fields:) → spawns Task
    → TransactionsService.updateTransaction() → async throws
      → FirestoreRepository.update() → try await collectionRef.document(id).updateData(fields)
        → Firestore writes to local cache → triggers snapshot listener on background queue
          → ProjectContext listener callback → Task { @MainActor in self?.transactions = newArray }
            → @Observable triggers SwiftUI invalidation
              → TransactionDetailView.currentTransaction re-evaluates
                → receiptsSection re-evaluates with new data
                  → MediaGallerySection receives new attachments array
```

## Diagnostic Logging Added

Instrumented 4 points:
1. `uploadReceiptImage` — after building images array, before updateTransaction
2. `updateTransaction` — before and after Firestore write
3. `ProjectContext` listener callback — when transactions array updates, with per-txn receiptImages counts
4. `receiptsSection` computed property — when SwiftUI evaluates it, with image count

## What the Logs Showed

### Test 1: Remove receipt (3 → 2) — Original code

- `updateTransaction: writing fields ["receiptImages"]` — write initiated
- `updateTransaction: Firestore write completed` — server ack'd
- `ProjectContext: listener fired with 6 transactions` — listener worked
- `txn INV_PURCHASE_...: 2 receiptImages` — correct data in listener
- `receiptsSection evaluated: 2 images` — SwiftUI re-evaluated with correct count
- **Visual did NOT update** — view showed stale 3 images

### Test 2: Add receipt (2 → 3) — Original code

- `uploadReceiptImage: built 3 images, calling updateTransaction` — upload succeeded
- `updateTransaction: writing fields ["receiptImages"]` — write initiated
- `updateTransaction: Firestore write completed` — server ack'd
- **ProjectContext listener NEVER fired** — no listener callback after write
- `receiptsSection evaluated: 2 images` — view kept showing stale count

### Key Finding

The remove case proves the full data flow works end-to-end:
- Firestore write succeeds
- Listener fires with correct data
- `@Observable` triggers re-evaluation
- `receiptsSection` evaluates with correct count (2 images)
- **But the visual output doesn't change**

## Attempted Fixes (All Reverted)

### 1. Removed `MemoryCacheSettings()` from emulator config

**Hypothesis:** `MemoryCacheSettings()` in `FirebaseEmulatorConfig.swift:36` prevents query-based snapshot listeners from firing on local writes.

**Result:** Remove case started working (listener fired), but add case still inconsistent. Visual update still didn't happen even when listener fired with correct data.

**File:** `LedgeriOS/Services/FirebaseEmulatorConfig.swift:36`

### 2. Made `update()` fire-and-forget (removed async/await)

**Hypothesis:** `try await updateData()` waits for server ack before the local cache write triggers listeners. Making it synchronous (like `create()` already is) would trigger listeners immediately.

**Changes:** Modified 20+ files — `FirestoreRepository.update()`, `RepositoryProtocol`, all 6 service protocols, all 6 service implementations, all callers (`TransactionDetailView`, `ItemDetailView`, `SpaceDetailView`, `ProjectDetailView`, `EditProjectModal`, `ReassignTransactionToProjectModal`, `ProjectContext.archiveProject`), test mocks.

**Result:** With completion handler logging, confirmed `updateData succeeded`. But listener still didn't fire for adds. And even when listener did fire (removes), visual still didn't update.

**Verdict:** The async/await vs fire-and-forget distinction didn't fix the rendering issue. The 20-file change was premature — should have been a single targeted test.

### 3. Added `.id()` modifiers on receipt sections

**Hypothesis:** `LazyVStack` caches rendered children and doesn't propagate visual updates. `.id(currentTransaction.receiptImages?.hashValue)` would force re-creation.

**Result:** Made things worse — error symbols appeared for previously deleted images (view was recreated from stale state), and updates still didn't visually propagate.

**Verdict:** `.id()` destroys and recreates the view, losing `@State` (like expanded section state). It's a blunt instrument that creates more problems than it solves.

### 4. Replaced `LazyVStack` with `VStack`

**Hypothesis:** `LazyVStack` is the root cause of visual caching.

**Result:** Not properly tested in isolation (was combined with other changes). Reverted.

## What We Know For Certain

1. **The Firestore write succeeds** — confirmed by completion handler and by data being correct on re-entry
2. **The snapshot listener fires (at least for removes)** — confirmed by ProjectContext logging
3. **SwiftUI re-evaluates `receiptsSection`** — confirmed by `let _ = print()` showing correct count
4. **The visual does not update** — the rendered output is stale despite correct data in the view body
5. **Navigating away and back fixes it** — the view renders correctly on fresh mount

## Remaining Hypotheses (Not Yet Tested)

### A. `LazyVStack` visual caching (isolated test needed)

`LazyVStack` at `TransactionDetailView.swift:105` may cache the rendered output of static children. Even though the body re-evaluates with correct data, `LazyVStack` may not re-render the actual pixels. Needs isolated testing: change ONLY `LazyVStack` → `VStack` (keeping `pinnedViews` via a Section if needed) and test.

### B. `MediaGallerySection` or `ThumbnailGrid` identity issue

`MediaGallerySection` takes `attachments: [AttachmentRef]` as a `let`. Even if new values are passed, the child `ThumbnailGrid` may not update if SwiftUI considers it structurally identical. Check if `AttachmentRef` needs `Equatable` conformance or if `ThumbnailGrid` has internal caching.

### C. `CollapsibleSection` content closure evaluation

`CollapsibleSection` uses `@ViewBuilder let content: () -> Content`. The closure captures values at creation time. If SwiftUI doesn't re-evaluate the closure when the parent changes (because the `CollapsibleSection` identity is stable), the inner `MediaGallerySection` would receive stale data.

### D. Async image loading masking the update

`ThumbnailGrid` likely uses `AsyncImage` for thumbnails. Even if the data updates, newly added images may not render immediately because `AsyncImage` needs to fetch the URL. The "stale" appearance might be correct rendering of a loading state that looks like nothing changed.

## Files of Interest

- `TransactionDetailView.swift:105` — `LazyVStack` containing all sections
- `TransactionDetailView.swift:424-449` — `receiptsSection` computed property
- `TransactionDetailView.swift:815-830` — `uploadReceiptImage`
- `TransactionDetailView.swift:918-933` — `updateTransaction` (fire-and-forget Task wrapper)
- `ProjectContext.swift:72-79` — Firestore snapshot listener for transactions
- `MediaGallerySection.swift` — receives `attachments: [AttachmentRef]` as let
- `CollapsibleSection.swift` — wraps content in `@ViewBuilder` closure
- `FirestoreRepository.swift:44-46` — `update()` with `async throws`
- `FirebaseEmulatorConfig.swift:36` — `MemoryCacheSettings()` for emulator
