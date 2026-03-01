# Firestore Emulator: "No Accounts Found" after Sign-In

**Status:** RESOLVED
**Created:** 2026-02-28
**Symptom:** User signs in successfully against Auth emulator, but AccountGateView shows "No Accounts Found." The `collectionGroup("users")` query returns 0 documents from the iOS SDK, even though the same query works via curl (REST).

---

## Environment

- App: SwiftUI iOS, bundle ID `apps.nine4.ledger`
- Simulator: iPhone 16e (`7CE5E513-69E1-4725-B2C4-94AB9721B2FE`)
- Xcode scheme: "LedgeriOS (Emulator)" — sets env var `USE_FIREBASE_EMULATORS=1`
- Firebase iOS SDK: 11.15.0 (visible in console logs)
- Emulators started with: `firebase emulators:start --import=./firebase-export --export-on-exit=./firebase-export`
- Emulator ports: Auth 9099, Firestore 8181, Storage 9199, UI 4000

### Emulator data (confirmed present)

- Auth user: `team@nine4.co` / `password123` → UID `4ef35958-597c-4aea-b99e-1ef62352a72d`
- Account doc: `accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94`
- Membership doc: `accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/users/<docId>` with field `uid: "4ef35958-597c-4aea-b99e-1ef62352a72d"`

---

## Investigation Timeline

### 1. Initial symptom triage

**Hypothesis:** `discoverAccounts()` is never called — uid is nil when `.task` fires due to auth state listener timing.

**Evidence:** Added diagnostic `print("🟡 ...")` statements to:
- `AccountGateView.swift` `.task` block
- `AccountContext.discoverAccounts()`
- `SignInView.signIn()`
- `FirebaseEmulatorConfig.configureIfEnabled()`

**Result:** RULED OUT. Console showed:
```
🟡 AccountGateView.task: uid=4ef35958-597c-4aea-b99e-1ef62352a72d
🟡 AccountGateView.task: calling discoverAccounts
🟡 discoverAccounts called for userId: 4ef35958-597c-4aea-b99e-1ef62352a72d
🟡 memberships returned: 0
🟡 discoverAccounts result: 0 accounts
```

The uid IS present. `discoverAccounts` IS called. But the query returns 0 memberships.

---

### 2. Security rules fix

**Hypothesis:** Firestore security rules block the `collectionGroup("users")` list query.

**Evidence:** `firebase/firestore.rules` line 67 had:
```
allow read: if signedIn() && request.auth.uid == uid;
```
This checks the path variable `{uid}` (document ID), but the `collectionGroup` query filters on the `uid` **field**. The rules engine can't prove they match, so it rejects the query with "Null value error for 'list'".

**Fix applied:** Changed to:
```
allow read: if signedIn() && resource.data.uid == request.auth.uid;
```

**Result:** PARTIALLY FIXED. The curl collectionGroup query now works:
```bash
TOKEN=$(curl -s "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake" \
  -H "Content-Type: application/json" \
  -d '{"email":"team@nine4.co","password":"password123","returnSecureToken":true}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('idToken',''))")

curl -s "http://localhost:8181/v1/projects/ledger-nine4/databases/(default)/documents:runQuery" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"structuredQuery":{"from":[{"collectionId":"users","allDescendants":true}],"where":{"fieldFilter":{"field":{"fieldPath":"uid"},"op":"EQUAL","value":{"stringValue":"4ef35958-597c-4aea-b99e-1ef62352a72d"}}}}}'
```
Returns the membership doc. But the iOS SDK still returns 0.

---

### 3. Hypothesis: Firestore emulator config uses wrong API

**Hypothesis:** `FirebaseEmulatorConfig` sets Firestore emulator connection via manual `settings.host` instead of using the `useEmulator(withHost:port:)` API (which Auth already uses). The old approach may not properly configure the gRPC channel.

**Original code:**
```swift
let settings = Firestore.firestore().settings
settings.host = "\(host):\(firestorePort)"
settings.isSSLEnabled = false
settings.cacheSettings = MemoryCacheSettings()
Firestore.firestore().settings = settings
```

**Fix applied:** Changed to:
```swift
let firestore = Firestore.firestore()
firestore.useEmulator(withHost: host, port: firestorePort)
let settings = firestore.settings
settings.cacheSettings = MemoryCacheSettings()
firestore.settings = settings
```

**Result:** DID NOT FIX THE ISSUE. Console output after the fix:

```
[Firebase] Firestore emulator configured — host: localhost:8181, ssl: true
```

Key finding: **`ssl: true`** — the `useEmulator(withHost:port:)` method did NOT disable SSL. And the console shows SSL handshake errors:

```
Handshake failed with error SSL_ERROR_SSL: error:100000f7:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER
```

```
WatchStream (313033623365623338) Stream error: 'Unavailable: failed to connect to all addresses;
last error: UNKNOWN: ipv4:127.0.0.1:8181: Ssl handshake failed (TSI_PROTOCOL_FAILURE):
SSL_ERROR_SSL: error:100000f7:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER'
```

The SDK is trying to make an SSL/TLS connection to the emulator, which only speaks plain HTTP. The gRPC handshake fails, so the query returns 0 docs (from empty local cache) instead of throwing an error.

---

### 4. SSL not disabled by useEmulator

**Hypothesis:** `useEmulator(withHost:port:)` doesn't disable SSL in Firebase iOS SDK v11.15.0. The emulator speaks plain-text gRPC, so the TLS handshake fails.

**Evidence:** Console showed `ssl: true` and repeated `WRONG_VERSION_NUMBER` SSL errors. The SDK fell back to offline mode and returned 0 docs from empty memory cache.

**Fix applied:** Added `settings.isSSLEnabled = false` after `useEmulator(withHost:port:)`:
```swift
let firestore = Firestore.firestore()
firestore.useEmulator(withHost: host, port: firestorePort)
let settings = firestore.settings
settings.isSSLEnabled = false
settings.cacheSettings = MemoryCacheSettings()
firestore.settings = settings
```

**Result:** FIXED SSL. Console now shows `ssl: false`. Firestore emulator connection works — **collectionGroup query now returns 1 doc!** But: `memberships returned: 0` — the doc is fetched but then dropped during Codable decode.

---

### 5. Codable decode silently fails — doc fetched but dropped by compactMap

**Hypothesis:** `try? doc.data(as: AccountMember.self)` silently returns nil because the Firestore document has fields the Swift model can't decode.

**Evidence:** Console output:
```
🟡 collectionGroup query returned 1 docs
🟡   doc path: accounts/1dd4fd75-8eea-4f7a-98e7-bf45b987ae94/users/4ef35958-597c-4aea-b99e-1ef62352a72d
🟡   data: ["createdBy": ..., "accountId": ..., "isDisabled": 0, "updatedBy": <null>,
           "role": admin, "deletedAt": <null>, "id": ..., "updatedAt": ..., "uid": ..., "createdAt": ...]
🟡 memberships returned: 0   ← compactMap dropped the doc
```

The doc has extra fields not in Swift model: `createdBy`, `isDisabled`, `updatedBy`, `deletedAt`.
The Swift `AccountMember` model has: `id`, `accountId`, `uid`, `role`, `email`, `name`, `createdAt`, `updatedAt`.

The RN version uses a forgiving `normalizeAccountMemberFromFirestore()` that spreads whatever data exists — no strict schema validation. The Swift version uses `Codable` with `try?` which fails and silently returns nil.

**Fix applied:** Changed `try?` to `do/catch` with error logging:
```swift
do {
    var member = try doc.data(as: AccountMember.self)
    ...
} catch {
    print("🔴 AccountMember decode failed for \(doc.reference.path): \(error)")
    return nil
}
```

**Result:** Error revealed:
```
🔴 AccountMember decode failed: typeMismatch(Swift.Dictionary<Swift.String, Any>,
    codingPath: [CodingKeys(stringValue: "createdAt")],
    debugDescription: "Expected to decode Dictionary<String, Any> but found a string/data instead.")
```

**Root cause:** `@ServerTimestamp var createdAt: Date?` expects a Firestore native `Timestamp` object
(which decodes as a dictionary with `_seconds`/`_nanoseconds`), but the emulator import stored timestamps
as ISO 8601 strings (`"2025-11-07T01:00:51.075+00:00"`). The Firestore Codable decoder can't decode
a string as a Timestamp dictionary, so the entire decode fails.

The RN app never hits this because `normalizeAccountMemberFromFirestore` types timestamps as `unknown`
and doesn't validate them at runtime.

**Fix applied:** Removed `@ServerTimestamp` from both fields and added explicit `CodingKeys` that
exclude `createdAt` and `updatedAt` from decoding:
```swift
struct AccountMember: Codable, ... {
    @DocumentID var id: String?
    var accountId: String?
    var uid: String?
    var role: MemberRole?
    var email: String?
    var name: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountId, uid, role, email, name
    }
}
```

Timestamps are nil when decoded but aren't needed for discovery or current UI. Extra doc fields
(`createdBy`, `isDisabled`, `updatedBy`, `deletedAt`) are ignored since they're not in CodingKeys.

**Result:** FIXED. Account discovery works — user sees their account after sign-in.

**Note:** Other models using `@ServerTimestamp` may have the same issue with emulator data.
Check `Account`, `Item`, `Transaction`, `Space`, `BudgetCategory` etc. if similar decode
failures appear downstream.

---

## Files Modified

| File | Change |
|------|--------|
| `firebase/firestore.rules:67` | Changed `request.auth.uid == uid` → `resource.data.uid == request.auth.uid` |
| `LedgeriOS/Services/FirebaseEmulatorConfig.swift` | Uses `useEmulator(withHost:port:)` + `isSSLEnabled = false` |
| `LedgeriOS/Models/AccountMember.swift` | Removed `@ServerTimestamp`, added `CodingKeys` excluding timestamps |
| `LedgeriOS/Services/AccountMembersService.swift` | Diagnostic logging + `do/catch` instead of `try?` for decode errors |
| `LedgeriOS/State/AccountContext.swift` | Added diagnostic logging in `discoverAccounts` |
| `LedgeriOS/Views/AccountGateView.swift` | Added diagnostic logging in `.task` |
| `LedgeriOS/Auth/SignInView.swift` | Added diagnostic logging in `signIn()` |

## Diagnostic logging added (still in codebase)

All `print("🟡 ...")` and `print("🔴 ...")` statements. Filter console with `🟡` or `🔴` to see diagnostic output.
