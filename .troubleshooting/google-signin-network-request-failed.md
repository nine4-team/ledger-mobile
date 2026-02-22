# Issue: Google Sign-In Fails with auth/network-request-failed

**Status:** Active
**Opened:** 2026-02-21
**Resolved:** _pending_

## Info
- **Symptom:** Tapping "Sign In with Google" shows an Alert: "Google Sign-In Failed — [auth/network-request-failed] A network error has occurred, please try again." Device has WiFi connectivity.
- **Affected area:** `app/(auth)/sign-in.tsx`, `src/auth/authStore.ts`, `src/firebase/firebase.ts`

### Auth Flow
1. `sign-in.tsx:258` `handleGoogleSignIn()` checks `isOnline` → calls `signInWithGoogle()`
2. `authStore.ts:121` calls `GoogleSignin.signIn()` (Google OAuth native flow)
3. If successful, gets idToken → creates Firebase credential
4. `authStore.ts:136` calls `auth.signInWithCredential(credential)` (Firebase Auth)

The `[auth/network-request-failed]` error code comes from Firebase Auth, not from GoogleSignin itself. This means step 2 (`GoogleSignin.signIn()`) **succeeds** (Google OAuth completes and returns an idToken), but step 4 (`auth.signInWithCredential()`) **fails** because the Firebase Auth module is pointed at `localhost:9099` (the emulator) — which is unreachable on a physical device.

### Emulator Configuration (`.env`)
```
EXPO_PUBLIC_USE_FIREBASE_EMULATORS=true
EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST=localhost
EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_PORT=9099
```

`src/firebase/firebase.ts:37-41` unconditionally calls `authInstance.useEmulator('http://localhost:9099')` when the flag is set. On a physical device, `localhost` refers to the device itself, not the Mac running the emulator. The Firebase Auth emulator is not running on the device → network timeout → `auth/network-request-failed`.

### Bundle ID Discrepancy (secondary finding)
- `GoogleService-Info.plist:16` has `BUNDLE_ID = apps.nine4.ledger`
- Xcode / `app.json` uses `com.nine4.ledger`
- This mismatch could affect Firebase's ability to validate the app, but likely doesn't affect the Google OAuth step itself.

### Packages
- `@react-native-google-signin/google-signin`: ^16.1.1
- `@react-native-firebase/auth`: ^21.0.0
- `expo`: ~52.0.0

## Experiments

### H1: Firebase Auth emulator not running — `localhost:9099` connection refused
- **Rationale:** `.env` has `EXPO_PUBLIC_USE_FIREBASE_EMULATORS=true` → `authInstance.useEmulator('http://localhost:9099')` is called at init. On the simulator, `localhost` resolves to the Mac, but if the Firebase Auth emulator is not actively running, the connection is refused. `auth.signInWithCredential()` tries to POST to `http://localhost:9099` → ECONNREFUSED → `auth/network-request-failed`.
- **Experiment:** Ran `lsof -i :9099` — no process is listening on port 9099.
- **Result:** **Nothing is listening on port 9099.** Firebase Auth emulator is not running. Connection refused is the direct cause.
- **Verdict:** Confirmed

### H2: Bundle ID mismatch in GoogleService-Info.plist (`apps.nine4.ledger` vs `com.nine4.ledger`)
- **Rationale:** Firebase uses `BUNDLE_ID` from the plist to validate the app. If the running bundle ID doesn't match, Firebase may reject the credential exchange.
- **Experiment:** Check if the error persists after fixing the bundle ID in `GoogleService-Info.plist` to `com.nine4.ledger`.
- **Result:** _pending_
- **Verdict:** Inconclusive (secondary to H1 — fix H1 first)

## Resolution
_Do not fill this section until the fix is verified — either by a passing
test/build or by explicit user confirmation. Applying a fix is not verification._

- **Root cause:**
- **Fix:**
- **Files changed:**
- **Lessons:**
