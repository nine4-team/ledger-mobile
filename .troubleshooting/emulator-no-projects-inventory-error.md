# Issue: Emulator — No Projects, Inventory Error, Cloud Function Crash

**Status:** Active
**Opened:** 2026-02-28
**Resolved:** _pending_

## Info
- **Symptom:** After successful login against Auth emulator, Projects screen shows "No Active Projects." Inventory screen crashes with fatal error. Cloud Function logs show `onAccountMembershipCreated` failing with "Firestore transactions require all reads to be executed before all writes."
- **Affected area:** All Firestore data models, Cloud Function `ensureBudgetCategoryPresetsSeeded`, Projects screen, Inventory screen

**Background:** Previous issue (RESOLVED in `firestore-emulator-no-accounts.md`) identified that `@ServerTimestamp` fields decode incorrectly from emulator-exported data because timestamps are stored as ISO 8601 strings, not native Firestore Timestamp objects. The fix was applied to `AccountMember` only. The resolution note explicitly warned that other models would have the same issue.

## Experiments

### H1: All other Swift models with @ServerTimestamp are silently failing decode — same root cause as AccountMember fix
- **Rationale:** 12 models still have `@ServerTimestamp` on `createdAt`/`updatedAt` with no CodingKeys exclusion. Emulator export stores timestamps as ISO strings. `try? data(as:)` silently returns nil. compactMap drops all docs.
- **Experiment:** Read all model files, check for @ServerTimestamp without CodingKeys exclusion
- **Result:** CONFIRMED. 12 models affected:
  - `Project.swift` — @ServerTimestamp createdAt, updatedAt, no CodingKeys
  - `Account.swift` — same
  - `Item.swift` — same
  - `Transaction.swift` — same
  - `Space.swift` — same
  - `BudgetCategory.swift` — same
  - `ProjectBudgetCategory.swift` — same
  - `ProjectPreferences.swift` — same
  - `BusinessProfile.swift` — @ServerTimestamp updatedAt, no CodingKeys
  - `SpaceTemplate.swift` — same
  - `Invite.swift` — @ServerTimestamp createdAt, no CodingKeys
  - `VendorDefaults.swift` — @ServerTimestamp updatedAt, no CodingKeys
- **Fix applied:** Removed `@ServerTimestamp` from all 12 models. Added `CodingKeys` enums that exclude `createdAt`/`updatedAt`. Also added `import Foundation` to `BusinessProfile.swift` and `VendorDefaults.swift` which had their `import FirebaseFirestore` removed (Foundation was previously available transitively).
- **Verdict:** Fix applied — **not yet verified** (two new issues emerged before verification)

### H2: Cloud Function transaction bug causes onAccountMembershipCreated to fail
- **Rationale:** Error message is explicit: "Firestore transactions require all reads to be executed before all writes." Stack trace points to `ensureBudgetCategoryPresetsSeeded` at index.js:859.
- **Experiment:** Read TypeScript source to identify read/write ordering
- **Result:** CONFIRMED. `ensureBudgetCategoryPresetsSeeded` inside a transaction does:
  1. Read (existingFurnishings query)
  2. Write (conditional set)
  3. Read (seedRef get) — ILLEGAL: read after write
  4. Write (seedRef set)
  5. Read (accountPresetsRef get) — ILLEGAL: read after write
  6. Write (accountPresetsRef set)
- **Fix applied:** Restructured into PHASE 1 (all reads via `Promise.all`) then PHASE 2 (all writes). `npm run build` compiled clean.
- **Verdict:** Fix applied — **not yet verified**

### H3: Firestore emulator connection refused — IPv6 vs IPv4 mismatch
- **Rationale:** Console log shows `[C1 ::1.8181 in_progress socket-flow] ... Connection refused` and `Socket SO_ERROR [61: Connection refused]`. Error 61 = ECONNREFUSED. The connection target is `::1` (IPv6 loopback). Firebase CLI emulator binds to `127.0.0.1` (IPv4) by default. macOS may resolve `localhost` → `::1`, which gets refused.
- **Experiment:** Read `FirebaseEmulatorConfig.swift` to check what host string is passed to `useEmulator(withHost:port:)`. If it's `"localhost"`, try changing to `"127.0.0.1"`.
- **Result:** CONFIRMED. `FirebaseEmulatorConfig.swift` had `static let host = "localhost"`. Changed to `"127.0.0.1"`. After rebuild, console shows `Firestore emulator configured — host: 127.0.0.1:8181` with no ECONNREFUSED errors. `curl -s -H "Authorization: Bearer owner" http://127.0.0.1:8181/v1/projects/ledger-c3796/databases/(default)/documents/accounts` returns `{}` — connection works, but emulator has no data loaded.
- **Verdict:** Fix applied and verified — connection issue resolved. However, the emulator has **no data** — it was started without importing the export directory (`firebase-export-1772330570241o7vIWl/`).

### H4: InventoryContext missing from SwiftUI environment
- **Rationale:** Fatal crash: `No Observable object of type InventoryContext found. A View.environmentObject(_:) for InventoryContext may be missing as an ancestor of this view.`
- **Experiment:** Read `LedgerApp.swift` to check what contexts are injected. Read wherever `InventoryContext` is defined to understand what it needs.
- **Result:** CONFIRMED via `LedgerApp.swift` (lines 6-9): only `authManager`, `accountContext`, and `projectContext` are declared and injected. `InventoryContext` does not exist in the app entry point at all — it is neither declared, instantiated, nor passed via `.environment()`. This is a missing implementation.
- **Fix applied:** Added `@State private var inventoryContext: InventoryContext` to `LedgerApp`. Initialized in `init()` with `itemsService`, `transactionsService`, `spacesService` (same services already created for other contexts). Injected via `.environment(inventoryContext)` in the body. App launches without crash — Inventory tab is accessible.
- **Verdict:** Fix applied and verified — crash resolved

### H5: Emulator started without data import — RESOLVED
- **Rationale:** After H3 and H4 fixes, app connects to emulator without errors but shows no data. Emulator was started manually without `--import`.
- **Experiment:** Query Firestore emulator REST API; run seed script manually.
- **Result:** RESOLVED. Created `scripts/dev-native.mjs` and `npm run dev:native` — mirrors `npm run dev` but builds/launches the SwiftUI app instead of Metro. It starts emulators with `--import=./firebase-export`, seeds Firestore (1027 docs), seeds Storage, creates auth user, builds with the `LedgeriOS (Emulator)` scheme, and launches in the simulator. Seed confirmed working — REST API shows 2 projects in `accounts/1dd4fd75.../projects`.
- **Verdict:** Fixed. `npm run dev:native` is the one-command workflow for the native app. (Minor fix applied: `-showBuildSettings` needed `-destination` to return simulator path instead of device path.)

### H6: Project model decode failure — `budgetSummary.categories` shape mismatch (CURRENT BLOCKER)
- **Rationale:** After H5 fix, emulator has data (2 projects confirmed via REST API), but app still shows "No Active Projects." `FirestoreRepository.subscribe` (line 56) uses `try? $0.data(as: T.self)` which silently drops documents that fail to decode.
- **Experiment:** Fetched full Firestore document for project `0ee567e7-ae7b-4816-910f-2296368a6e60` via REST API. Compared field-by-field against `Project.swift` model.
- **Result:** CONFIRMED. Two problems found:
  1. **`budgetSummary.categories` is a MAP in Firestore but `[BudgetSummaryCategory]` (array) in Swift.** The Firestore doc stores categories as `{"categoryId": {fields...}}` (a map keyed by category ID). The Swift `ProjectBudgetSummary` struct declares `var categories: [BudgetSummaryCategory]?` which expects a JSON array. This type mismatch causes `Codable` decode to throw, and `try?` silently returns nil.
  2. **Extra fields in Firestore not in model:** `createdBy`, `updatedBy`, `deletedAt`, `metadata`, `budgetSummary.spentCents`, `budgetSummary.updatedAt`, and per-category fields `categoryType`, `isArchived`, `excludeFromOverallBudget`, `name`, `spentCents`. These are tolerated by `Codable` (extra keys are ignored by default) — NOT the cause. The categories shape mismatch IS the cause.
- **Firestore document fields:**
  ```
  accountId: (string) "1dd4fd75..."
  budgetSummary: (map) { totalBudgetCents: 13200100, spentCents: 12051405, categories: { "1aa4b56b...": { name: "Additional Requests", ... }, ... }, updatedAt: ... }
  clientName: (string) "Debbie Hyer"
  createdAt: (string) "2025-12-15T00:15:31+00:00"   ← ISO string, excluded via CodingKeys ✓
  createdBy: (string) "4ef35958..."                   ← not in model, ignored ✓
  deletedAt: (null)                                   ← not in model, ignored ✓
  description: (string) "6 Bed Rental Unit..."
  id: (string) "0ee567e7..."
  mainImageUrl: (null)
  metadata: (map) {}                                  ← not in model, ignored ✓
  name: (string) "Hyer's Martinique Rental"
  updatedAt: (string) "2026-01-24T00:27:12..."       ← ISO string, excluded via CodingKeys ✓
  updatedBy: (string) "4ef35958..."                   ← not in model, ignored ✓
  ```
- **Verdict:** Confirmed — `ProjectBudgetSummary.categories` type mismatch is the decode failure. Fix requires changing the Swift type from `[BudgetSummaryCategory]?` to `[String: BudgetSummaryCategory]?` (a dictionary keyed by category ID), and adding missing fields to `BudgetSummaryCategory` (`categoryType`, `isArchived`, `excludeFromOverallBudget`, `name`, `spentCents`). Also add `spentCents` and `updatedAt` to `ProjectBudgetSummary`.

### H6: Project model decode failure — `budgetSummary.categories` shape mismatch — FIXED
- **Fix applied:**
  1. `ProjectBudgetSummary.categories`: `[BudgetSummaryCategory]?` → `[String: BudgetSummaryCategory]?` (dictionary keyed by category ID, matching Firestore map)
  2. Added to `ProjectBudgetSummary`: `var spentCents: Int?`
  3. Added to `BudgetSummaryCategory`: `var spentCents: Int?`, `var name: String?`, `var categoryType: String?`, `var isArchived: Bool?`, `var excludeFromOverallBudget: Bool?`
  4. Removed `budgetCategoryId` from `BudgetSummaryCategory` (keyed by ID in the dictionary)
- **Verdict:** Fix applied. ModelCodableTests updated and passing.

### H7: Item model decode failure — `name` is null in Firestore but non-optional in Swift — FIXED
- **Rationale:** Found while auditing all models per H6 handoff notes. All items in the emulator have `name: null`; the display text is stored in `description`. Swift model had `name: String = ""` which Codable cannot decode from JSON null (default value only applies when key is absent, not when value is null).
- **Fix applied:**
  1. Changed `Item.name` from `String = ""` to `String?`
  2. Added `Item.description: String?` to capture the Firestore field
  3. Added computed `Item.displayName: String` that returns `name ?? description ?? ""`
  4. Updated 14 files (Views, Components, Modals, Logic) to use `item.displayName` instead of `item.name` for display purposes
  5. Write sites (`item.name = parsed.name`) left unchanged
- **Verdict:** Fix applied. All 400 tests pass.

### H8: Transaction CodingKey mismatches — silent data loss — FIXED
- **Rationale:** Found while auditing all models. Firestore stores `type` but Swift CodingKeys mapped to `transactionType` (no alias). Same for `receiptEmailed` → `hasEmailReceipt`.
- **Fix applied:**
  1. `case transactionType = "type"` — maps Swift property to Firestore field name
  2. `case hasEmailReceipt = "receiptEmailed"` — maps Swift property to Firestore field name
- **Verdict:** Fix applied. Tests updated and passing.

### H9: Decode error logging added to FirestoreRepository — DONE
- Replaced all `try? $0.data(as: T.self)` with `do/catch` that logs via `os.log` at error level
- Subsystem: `apps.nine4.ledger`, category: `FirestoreRepository`
- View in Console.app or via: `log show --predicate 'subsystem == "apps.nine4.ledger"' --last 30s`
- Would have caught H1, H6, H7 immediately

### H10: Firestore permissions error — auth token mismatch after emulator restart
- **Symptom:** After H6-H9 fixes, app connects but all Firestore queries return "Missing or insufficient permissions"
- **Root cause:** Emulator was restarted without importing auth state. The Firebase Auth emulator had 0 users. The app was signed in with a cached keychain token from a previous emulator session (wrong UID). Firestore rules require `isAccountMember(accountId)` which checks `accounts/{accountId}/users/{request.auth.uid}`.
- **Fix:** Created auth user via `node firebase/functions/scripts/create-auth-user.mjs`. Erased simulator to clear keychain (`xcrun simctl erase`). On next launch, user must sign in fresh with `team@nine4.co` / `password123`.
- **Verdict:** Auth user exists (UID `4ef35958...`), membership doc confirmed at `accounts/1dd4fd75.../users/4ef35958...`. Sign-in not yet completed (requires manual interaction in Simulator). All model fixes verified via 400 passing tests.

### H11: `dev-native.mjs` not passing USE_FIREBASE_EMULATORS env var to simctl launch — FIXED
- **Symptom:** After signing in, console showed `Firestore settings — host: firestore.googleapis.com, ssl: true` — connecting to PRODUCTION, not emulator.
- **Root cause:** `xcrun simctl launch` doesn't inherit Xcode scheme env vars. The scheme sets `USE_FIREBASE_EMULATORS=1` but simctl bypasses it. `FirebaseEmulatorConfig.isEnabled` checks `ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATORS"]`.
- **Fix:** Added `SIMCTL_CHILD_USE_FIREBASE_EMULATORS: '1'` to the `run()` call in `dev-native.mjs`. The `SIMCTL_CHILD_` prefix tells simctl to forward env vars to the launched app with the prefix stripped.
- **Verdict:** Confirmed — after fix, logs show BudgetCategory decode attempts (emulator data), not "Missing or insufficient permissions" (production).

### H12: BudgetCategoryType missing `standard` case — FIXED
- **Symptom:** After H11 fix, 3 BudgetCategory docs fail decode. H9 logging catches them immediately.
- **Root cause:** Firestore data has `metadata.categoryType: "standard"` but `BudgetCategoryType` enum only had `general, itemized, fee`.
- **Fix:** Added `standard` case to `BudgetCategoryType` enum in `Enums.swift`. Updated exhaustive switches in `CategoryRow.swift` and `BudgetTabCalculations.swift` to group `standard` with `general`.
- **Verdict:** Fix applied. Cannot verify decode success until manual sign-in.

### H12b: Improved FirestoreRepository decode error logging
- Changed from `error.localizedDescription` (generic) to `DecodingError` pattern matching with coding path and debug description. Falls through to `String(describing: error)` for non-DecodingError types.

## Handoff Notes

**Completed across sessions:**
- H1: @ServerTimestamp removal from 12 models
- H2: Cloud Function transaction read/write reorder
- H3: IPv6→IPv4 host fix in FirebaseEmulatorConfig
- H4: InventoryContext wired up in LedgerApp
- H5: `npm run dev:native` one-command workflow
- H6: ProjectBudgetSummary.categories array→dictionary
- H7: Item.name null decode + displayName computed property (14 files updated)
- H8: Transaction CodingKey aliases for `type` and `receiptEmailed`
- H9: Decode error logging via os.log in FirestoreRepository
- H10: Auth user re-created, simulator erased for clean keychain
- H11: `SIMCTL_CHILD_USE_FIREBASE_EMULATORS=1` in dev-native.mjs simctl launch
- H12: BudgetCategoryType `standard` case added

**To verify (requires manual interaction):**
1. Open Simulator (iPhone 16e should be booted)
2. Sign in with `team@nine4.co` / `password123`
3. Confirm projects appear on Projects screen
4. Tap Inventory tab, confirm items load with display names
5. Check Console.app / `log show` for any remaining decode errors

**Or use the full automated flow:** `npm run dev:native` (starts emulators, seeds data, creates auth user, builds and launches the app — but you still need to sign in manually).

## Resolution
_Pending manual sign-in verification. All code fixes are applied. Binary installed and running on iPhone 16e simulator._
