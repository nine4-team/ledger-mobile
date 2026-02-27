---
work_package_id: WP00
title: MediaService Prerequisite
lane: "doing"
dependencies: []
base_branch: main
base_commit: 23d2af72bc649ac3a4b27c26cc96cd1edd5b7b99
created_at: '2026-02-27T02:01:37.422707+00:00'
subtasks:
- T001
- T002
- T003
- T004
phase: Phase 0 - Foundation
assignee: ''
agent: ''
shell_pid: "70120"
review_status: ''
reviewed_by: ''
history:
- timestamp: '2026-02-26T22:30:00Z'
  lane: planned
  agent: system
  action: Prompt generated via /spec-kitty.tasks
---

# Work Package Prompt: WP00 – MediaService Prerequisite

## ⚠️ IMPORTANT: Review Feedback Status

- **Has review feedback?**: Check `review_status` above. If `has_feedback`, address the Review Feedback section before anything else.

---

## Review Feedback

*[Empty — no feedback yet.]*

---

## Objectives & Success Criteria

- `Item.swift` gains a `quantity: Int?` field that round-trips cleanly through Firestore Codable.
- `MediaService` can upload a `Data` (JPEG) to Firebase Storage and return a download URL string.
- `MediaService` can delete a stored file given its URL.
- `MediaGallerySection`'s add/remove/set-primary callbacks are wired to `MediaService` — no more stubs.
- Swift Testing tests cover MediaService upload/download/delete happy paths and error cases.
- No other WP is blocked on image upload after WP00 lands.

**To start implementing:** `spec-kitty implement WP00`

---

## Context & Constraints

- **Project**: Native SwiftUI iOS app in `LedgeriOS/LedgeriOS/`. Firebase Swift SDK via SPM only.
- **Tech refs**: `plan.md` (WP00 section), `data-model.md` (Item model gap), `spec.md` FR-16.8, FR-16.9.
- **Architecture**: `@MainActor @Observable` classes injected via `.environment()`. See `Auth/AuthManager.swift` as the pattern reference.
- **Storage SDK**: Use `putData(_ data: Data, metadata: StorageMetadata?)` — NOT `putFile()`. Upload path: `accounts/{accountId}/{entityType}/{entityId}/{filename}`.
- **Image picker**: SwiftUI `PhotosPicker` (iOS 16+) — `PhotosPickerItem` → `loadTransferable(type: Data.self)` to get JPEG data.
- **No CocoaPods, no XCTest** — Swift Testing (`@Test`, `#expect`, `@Suite`) only.
- **MediaGallerySection**: already exists in the Phase 5 component library. It has `onAdd`, `onRemove`, `onSetPrimary` callbacks. Wire these to `MediaService` calls.
- **Constraints**: offline-first — MediaService upload is one of the exceptions where actual connectivity is required (spec says "Only block on connectivity for: Firebase Storage uploads").

---

## Subtasks & Detailed Guidance

### Subtask T001 – Add `quantity: Int?` to `Item.swift`

**Purpose**: `quantity` is missing from the Item model but required by ItemDetailView (hero card) and NewItemView creation form.

**Steps**:
1. Open `Models/Item.swift`.
2. Add `var quantity: Int?` to the struct body.
3. In `CodingKeys`, add `case quantity` (Firestore field name is `quantity` — no mapping needed).
4. If `Item` has a custom `init(from:)`, add decoding: `quantity = try? container.decode(Int.self, forKey: .quantity)`.
5. Build to confirm no compile errors.

**Files**:
- `Models/Item.swift` (modify)

**Parallel?**: Yes — independent of T002.

**Notes**: This is a non-breaking additive change. Existing documents without `quantity` will decode to `nil`, which is correct.

---

### Subtask T002 – Create `MediaService.swift`

**Purpose**: Centralized Firebase Storage service. Every screen that uploads/downloads/deletes images goes through this service.

**Steps**:
1. Create `Services/MediaService.swift`.
2. Declare `@MainActor @Observable final class MediaService`.
3. Inject `Storage.storage()` as a private dependency.
4. Implement `uploadImage(_ data: Data, path: String) async throws -> String`:
   - Create `StorageReference` at the given path.
   - Set metadata: `contentType = "image/jpeg"`.
   - Call `ref.putDataAsync(data, metadata: metadata)` (Firebase SDK async method).
   - After upload, call `ref.downloadURL()` to get the URL.
   - Return `url.absoluteString`.
5. Implement `deleteImage(url: String) async throws`:
   - Create reference from URL: `Storage.storage().reference(forURL: url)`.
   - Call `ref.delete()`.
6. Implement `uploadPath(accountId: String, entityType: String, entityId: String, filename: String) -> String`:
   - Returns `"accounts/\(accountId)/\(entityType)/\(entityId)/\(filename)"`.
   - Caller generates filename (e.g., `UUID().uuidString + ".jpg"`).
7. Add `@Environment(MediaService.self) private var mediaService` usage pattern comment.

**Files**:
- `Services/MediaService.swift` (create, ~60 lines)

**Parallel?**: Yes — independent of T001.

**Notes**:
- Firebase Storage `putDataAsync` is the Swift concurrency-compatible method in the Firebase Swift SDK.
- Error types: `StorageErrorCode` — propagate to caller, don't swallow.
- Do NOT store `StorageReference` objects across async boundaries — always create fresh refs.

---

### Subtask T003 – Wire MediaService into MediaGallerySection

**Purpose**: `MediaGallerySection` currently has `onAdd`, `onRemove`, `onSetPrimary` callbacks that are likely stubs or no-ops. Wire them to `MediaService` calls.

**Steps**:
1. Open the existing `MediaGallerySection` component (find it in the Phase 5 component library — likely `Components/MediaGallerySection.swift`).
2. Read its current `onAdd: (Data) async throws -> AttachmentRef`, `onRemove: (AttachmentRef) async throws -> Void`, `onSetPrimary: (AttachmentRef) async throws -> Void` callback signatures (or whatever they are — adapt accordingly).
3. In the parent view (e.g., `TransactionDetailView` later, but for WP00 create a test harness or update the component itself):
   - `onAdd`: call `mediaService.uploadImage(data, path: mediaService.uploadPath(...))` → create `AttachmentRef` with the returned URL → append to the entity's images array → Firestore write.
   - `onRemove`: call `mediaService.deleteImage(url: ref.url)` → remove from images array → Firestore write.
   - `onSetPrimary`: update entity's `primaryImageUrl` field → Firestore write.
4. If `MediaGallerySection` uses `PhotosPicker` internally, confirm it passes `Data` (JPEG) to `onAdd`. If it passes `PhotosPickerItem`, handle `loadTransferable(type: Data.self)` inside the wiring layer.

**Files**:
- Existing `MediaGallerySection.swift` (read, may modify callback definitions)
- `Services/MediaService.swift` (add to from T002)

**Parallel?**: No — depends on T002.

**Notes**:
- The exact callback signatures depend on what Phase 5 built. Read the component first before assuming the API.
- This WP doesn't wire MediaService into any specific screen (that happens per-session). The goal is confirming the component + service integration pattern works.

---

### Subtask T004 – Write Swift Testing tests for MediaService

**Purpose**: Verify upload/download/delete paths and error handling before every subsequent WP relies on this service.

**Steps**:
1. Create `LedgeriOSTests/MediaServiceTests.swift` (or `LedgeriOSTests/Services/MediaServiceTests.swift`).
2. Add `@Suite struct MediaServiceTests`.
3. Write `@Test func uploadReturnsDownloadURL()`:
   - Use a mock/fake `StorageReference` that returns a preset URL. OR test against Firebase Emulator if configured.
   - Assert returned URL string is non-empty and valid.
4. Write `@Test func deleteCallsStorageDelete()`:
   - Confirm delete is called with the correct storage path derived from URL.
5. Write `@Test func uploadPathFormatsCorrectly()`:
   - Input: `accountId="acc1"`, `entityType="items"`, `entityId="item1"`, `filename="abc.jpg"`
   - Expected: `"accounts/acc1/items/item1/abc.jpg"`
   - This is a pure function — no mocking needed.
6. Write `@Test func uploadPathErrorThrows()`:
   - If Firebase Storage is unavailable, confirm the error propagates (not swallowed).

**Files**:
- `LedgeriOSTests/MediaServiceTests.swift` (create, ~80 lines)

**Parallel?**: No — depends on T002.

**Notes**:
- `uploadPath` is a pure function — test it directly, no mocking needed.
- For upload/delete tests involving Firebase Storage: if no emulator is configured, use dependency injection to pass a mock. Don't hit production Firebase in unit tests.
- Swift Testing syntax: `@Test func name() { #expect(result == expected) }`.

---

## Test Strategy

All tests use **Swift Testing** (`@Test`, `#expect`, `@Suite`) — NOT XCTest.

Pure function tests (`uploadPath`): call directly, assert result.

Service integration tests: inject a mock `StorageReference` via protocol or closure-based dependency injection. Do not rely on live Firebase connectivity in unit tests.

Run tests: Product → Test (⌘U) in Xcode, or `xcodebuild test -scheme LedgeriOS`.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Firebase Storage rules block test uploads | Use Firebase Emulator or mock the storage layer |
| `MediaGallerySection` callback signatures differ from assumption | Read the component first (Step 1 of T003) before writing wiring code |
| `putDataAsync` not available in current SDK version | Check Firebase Swift SDK version in `Package.resolved`; use `putData` + completion if needed |
| JPEG compression quality | Use `UIImage.jpegData(compressionQuality: 0.8)` — 80% quality is standard |

---

## Review Guidance

- [ ] `Item.quantity` field compiles and round-trips through Firestore decoding (nil when absent).
- [ ] `MediaService.uploadImage()` returns a non-empty URL string on success.
- [ ] `MediaService.deleteImage()` calls through to Firebase Storage delete.
- [ ] `uploadPath()` produces correctly formatted paths for all entity types.
- [ ] `MediaGallerySection.onAdd` callback wired to `MediaService` — no stubs remain.
- [ ] All 4+ tests pass in the test suite.
- [ ] No hardcoded colors, magic numbers, or XCTest imports.

## Activity Log

- 2026-02-26T22:30:00Z – system – lane=planned – Prompt created.
