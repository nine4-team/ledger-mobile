# Issue: Firestore "Missing or insufficient permissions" on iOS native app

**Status:** Resolved
**Opened:** 2026-02-25
**Resolved:** _pending_

## Info
- **Symptom:** Every Firestore query from the SwiftUI iOS app returns "Missing or insufficient permissions", including direct document reads to `accounts/{accountId}/users/{uid}` where the doc ID matches the authenticated user's UID.
- **Affected area:** `LedgeriOS/LedgeriOS/Views/FirestoreTestView.swift`, Firestore security rules at `firebase/firestore.rules`

### Background
- Firebase Auth works — user signs in successfully (email/password + Google Sign-In confirmed)
- The RN app uses `collectionGroup(db, 'users')` with `where('uid', '==', uid)` and it works
- Security rules use `isAccountMember(accountId)` which checks `exists(/accounts/{accountId}/users/{request.auth.uid})`
- Tried: bare `accounts` collection query (no filter) → permissions denied
- Tried: `collectionGroup("users")` with uid filter → permissions denied
- Tried: direct doc read at `accounts/{testAccountID}/users/{uid}` → permissions denied (current code)
- The test account ID is `1dd4fd75-8eea-4f7a-98e7-bf45b987ae94` (from `.env`)

### Questions to investigate
- Is `Auth.auth().currentUser` actually populated when the query runs?
- Is the Firebase Auth UID the same one that exists in the Firestore membership doc?
- Is the iOS app using the same Firebase project as the RN app?
- Are the deployed Firestore rules the same as the local `firebase/firestore.rules` file?
- Could the iOS bundle ID be missing from Firebase Console's authorized apps?

### Confirmed facts
- iOS and RN apps use identical `GoogleService-Info.plist` — same project (`ledger-nine4`), same bundle ID (`apps.nine4.ledger`), same API key, same GOOGLE_APP_ID. Not a config mismatch.

## Experiments

### H1: Auth.auth().currentUser is nil at query time (race condition)
- **Rationale:** AuthManager uses async listener; currentUser could be nil when button is tapped
- **Experiment:** Add diagnostic logging to print UID, email, token before query
- **Result:** _pending — need user to run and report console output_
- **Verdict:** _pending_

### H2: iOS GoogleService-Info.plist differs from RN project
- **Rationale:** Different Firebase project or bundle ID could cause auth tokens to be rejected
- **Experiment:** Compare plist files between LedgeriOS/ and ios/ directories
- **Result:** All three plist files are identical — same project (`ledger-nine4`), bundle ID (`apps.nine4.ledger`), keys
- **Verdict:** Ruled Out

### H3: Firestore rules reject direct doc reads to accounts/{id}/users/{uid}
- **Rationale:** `isAccountMember` does `exists()` on the same doc being read — possible circular dependency
- **Experiment:** Trace rule evaluation step by step for direct doc read
- **Result:** `exists()` in rules is a privileged server-side lookup — no circularity. Direct doc read at `accounts/{accountId}/users/{request.auth.uid}` SHOULD succeed if doc exists. Also confirmed collectionGroup on "users" has a conflict with top-level `/users/{uid}` rule (line 37) — but current code does direct reads, not collectionGroup.
- **Verdict:** Ruled Out (for direct reads; collectionGroup conflict is a separate issue for later)

### H4: Membership doc doesn't exist for this user's UID
- **Rationale:** If the iOS auth produces a different UID or the membership doc was never created, `exists()` returns false → permission denied
- **Experiment:** List Firebase Auth users via admin SDK, create account + membership docs in production Firestore
- **Result:** Confirmed — production Firestore was completely empty (all development was done against the emulator). Created `accounts/1dd4fd75-...`, `accounts/1dd4fd75-.../users/sHuIe2M85W...`, and `health/ping` using firebase-admin with gcloud ADC.
- **Verdict:** Confirmed — root cause

## Resolution

- **Root cause:** Production Firestore was empty. All RN development used the emulator. The iOS app pointed at production. Security rules' `isAccountMember()` calls `exists()` on the membership doc — which didn't exist — so every query was denied.
- **Fix:** Created the minimum docs in production Firestore via firebase-admin: account doc, owner membership doc, health/ping. Connection test and cache test both passed after.
- **Files changed:** None (data fix, not code fix)
- **Lessons:** When starting iOS development against a Firebase project that was developed against the emulator, seed production with at least one account + membership doc first. Consider a `seed-production.mjs` script alongside `setup-health-check.mjs` for future onboarding.
