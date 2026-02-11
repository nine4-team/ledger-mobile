# Issue: Emulator images not loading on start

**Status:** Active (fix applied, awaiting user verification)
**Opened:** 2026-02-11
**Resolved:** _pending_

## Info
- **Symptom:** Running `./start-emulators.sh` doesn't load images into the project. User expects images to be available in the emulators after startup.
- **Affected area:** `start-emulators.sh`, Firebase Storage emulator, `firebase-export/storage_export/`

### Background research

**Script:** `start-emulators.sh` runs:
```bash
firebase emulators:start --import=./firebase-export --export-on-exit=./firebase-export
```

**Firebase CLI version:** 14.1.0 (matches export metadata version 14.1.0)

**Export data on disk:**
- `firebase-export/storage_export/blobs/` — 1125 blob files (images), tracked in git
- `firebase-export/storage_export/metadata/` — 1125 metadata JSON files
- `firebase-export/storage_export/buckets.json` — originally listed two buckets: `demo-ledger.appspot.com`, `ledger-nine4.appspot.com`
- `firebase-export/firestore_export/` — only metadata file (15 bytes, essentially empty)
- `firebase-export/auth_export/` — accounts.json + config.json

**All storage blobs were in bucket `demo-ledger.appspot.com`** (verified across 20 metadata files).

**App native config (GoogleService-Info.plist):**
- `STORAGE_BUCKET` = `ledger-nine4.firebasestorage.app`

**`.firebaserc` project:** `ledger-nine4`

**App emulator connection (`src/firebase/firebase.ts:57-62`):**
- `storage()` → uses native config's default bucket → `ledger-nine4.firebasestorage.app`
- `useEmulator('localhost', 9199)` → connects to emulator, but bucket name stays from native config

**Port config (before fix):**
- Storage: firebase.json=9199, app fallback=9199 (match)
- Firestore: firebase.json=8081, .env=8080 (**MISMATCH**)

## Experiments

### H1: Bucket name mismatch — exported data in `demo-ledger.appspot.com` but app requests `ledger-nine4`
- **Rationale:** All 1125 storage blobs had `bucket: "demo-ledger.appspot.com"` in metadata. The app's native config sets `STORAGE_BUCKET=ledger-nine4.firebasestorage.app`. When the app calls `storage().ref(path)`, it targets the native config bucket, which doesn't match the imported data. The emulator would return "not found".
- **Experiment:** Update all 1125 metadata bucket names from `demo-ledger.appspot.com` → `ledger-nine4.appspot.com` and see if images load.
- **Result:** Migrated all 1125 metadata files and `buckets.json`. Verified no `demo-ledger` references remain in storage_export.
- **Verdict:** Fix applied — awaiting user verification.

### H2: Firestore port mismatch
- **Rationale:** `.env` set `EXPO_PUBLIC_FIRESTORE_EMULATOR_PORT=8080` but `firebase.json` configured Firestore on port `8081`. The app would connect to port 8080 (nothing there) instead of 8081.
- **Experiment:** Compare `.env` FIRESTORE port with `firebase.json` emulator port.
- **Result:** Confirmed mismatch: `.env`=8080, `firebase.json`=8081. Fixed by aligning both to port `8181`. Also updated fallback default in `src/firebase/firebase.ts`.
- **Verdict:** Confirmed and fixed.

## Changes applied
- `firebase.json`: Firestore emulator port 8081 → 8181
- `.env`: `EXPO_PUBLIC_FIRESTORE_EMULATOR_PORT` 8080 → 8181
- `src/firebase/firebase.ts`: fallback Firestore port `'8081'` → `'8181'`
- `firebase-export/storage_export/buckets.json`: removed `demo-ledger.appspot.com`, kept `ledger-nine4.appspot.com`
- `firebase-export/storage_export/metadata/*.json` (1125 files): `bucket` changed from `demo-ledger.appspot.com` → `ledger-nine4.appspot.com`

## Resolution
_Awaiting user verification — run `./start-emulators.sh` and confirm images load._
