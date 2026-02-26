# Issue: Google Sign-In crashes — "No active configuration. Make sure GIDClientID is set in Info.plist"

**Status:** Active
**Opened:** 2026-02-25
**Resolved:** _pending_

## Info
- **Symptom:** Google Sign-In throws NSInvalidArgumentException: "No active configuration. Make sure GIDClientID is set in Info.plist." This occurs in the native SwiftUI build (`LedgeriOS/`), not the React Native build.
- **Affected area:** `LedgeriOS/LedgeriOS/Auth/AuthManager.swift`, `LedgeriOS/LedgeriOS/LedgerApp.swift`, `LedgeriOS/LedgeriOS/Info.plist`

### Code reading

**LedgerApp.swift** calls `FirebaseApp.configure()` in `init()` and handles `GIDSignIn.sharedInstance.handle(url)` via `.onOpenURL`. AppDelegate also calls `FirebaseApp.configure()` but is NOT wired as `@UIApplicationDelegateAdaptor` — so it's unused (the `@main` SwiftUI App struct is the entry point).

**AuthManager.swift:42** calls `GIDSignIn.sharedInstance.signIn(withPresenting:)` — this is where the crash occurs because GIDSignIn has no client ID configured.

**Info.plist** has `CFBundleURLSchemes` with the reversed client ID (`com.googleusercontent.apps.351137650087-...`) — this handles the OAuth callback URL. But there is **NO `GIDClientID` key** in Info.plist.

**GoogleService-Info.plist** contains `CLIENT_ID = 351137650087-5ovflnobvvu4vrb7qrof5re6ro2mbtnv.apps.googleusercontent.com`. When `FirebaseApp.configure()` reads this, it sets up Firebase — but the GoogleSignIn SDK reads its client ID from a **separate** source: either `Info.plist` `GIDClientID` key, or an explicit `GIDConfiguration` object.

**Bundle ID:** Xcode project uses `apps.nine4.ledger` and `GoogleService-Info.plist` has `BUNDLE_ID = apps.nine4.ledger` — these match (unlike the React Native build which had a mismatch).

### Root cause analysis

The Google Sign-In SDK (v7+) requires the `GIDClientID` to be set in Info.plist OR configured programmatically via `GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID:)`. Neither is done. `FirebaseApp.configure()` sets up Firebase but does NOT automatically configure GIDSignIn.

## Experiments

### H1: Missing `GIDClientID` in Info.plist
- **Rationale:** The error message literally says "Make sure GIDClientID is set in Info.plist." Grepping for `GIDClientID` across the entire `LedgeriOS/` directory returns zero matches. The CLIENT_ID exists only in `GoogleService-Info.plist`, which the Google Sign-In SDK does not read automatically.
- **Experiment:** Check Info.plist for `GIDClientID` key.
- **Result:** No `GIDClientID` key in Info.plist. No programmatic `GIDConfiguration` setup either.
- **Verdict:** Confirmed

## Resolution
_Do not fill this section until the fix is verified — either by a passing
test/build or by explicit user confirmation. Applying a fix is not verification._

- **Root cause:**
- **Fix:**
- **Files changed:**
- **Lessons:**
