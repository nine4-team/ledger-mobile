# Firebase template (emulators + enforcement)

This folder is a **starter Firebase backend** for apps built from this template:

- Firestore rules (`firestore.rules`)
- Firestore indexes (`firestore.indexes.json`)
- Optional Cloud Functions (`functions/`) for authoritative operations like **quota enforcement**

## Emulators

Run from repo root:

```bash
firebase emulators:start
```

Ports (default):

- Auth: `9099`
- Firestore: `8080`
- Functions: `5001`
- Emulator UI: `4000`

## Emulator-First Development

The template is configured to connect to emulators by default in development:

- Set `EXPO_PUBLIC_USE_FIREBASE_EMULATORS=true` in `.env` (default)
- Start emulators: `firebase emulators:start`
- Start Expo: `npm start`

The app will automatically connect to emulators. To use production Firebase, set `EXPO_PUBLIC_USE_FIREBASE_EMULATORS=false`.

## Emulator UI

Access at `http://localhost:4000` to:

- **Auth**: Create test users, view user data
- **Firestore**: Browse collections, add/edit documents
- **Functions**: View logs, test functions
- **Reset**: Clear all emulator data

## Security Rules

The `firestore.rules` file includes:

- User profile access (users can read/write their own profile)
- Quota counter reads (users can read their own quotas)
- Quota counter writes blocked (only Cloud Functions can write)
- Quota'd object collections blocked (only Cloud Functions can write)

**Important**: Rules are guardrails, not enforcement. Always use Cloud Functions for authoritative quota/billing operations.

## Cloud Functions

### `createWithQuota`

Authoritative function to create objects with quota enforcement:

```typescript
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/firebase/firebase';

const createWithQuota = httpsCallable(functions, 'createWithQuota');

const result = await createWithQuota({
  objectKey: 'object', // Quota key from appConfig
  collectionPath: 'users/{uid}/objects', // Where to create the doc
  data: { title: 'My Object', ... }, // Document data
});
```

The function:
1. Checks current quota count
2. Validates against free limit
3. Creates document atomically with quota increment
4. Returns document ID or throws `resource-exhausted` error

### Customizing Quota Limits

Edit `firebase/functions/src/index.ts` to customize:
- Free limits per object type
- Pro user checks (integrate with RevenueCat webhooks)
- Per-object-type rules

## Deployment

### Deploy Rules

```bash
firebase deploy --only firestore:rules
```

### Deploy Functions

```bash
cd firebase/functions
npm install
npm run build
cd ../..
firebase deploy --only functions
```

### Deploy Everything

```bash
firebase deploy
```

## Recommended Enforcement Pattern

For any action that should be limited by **quota** or **billing**:

1. **Client-side check** (UX): Use `requireProOrQuota()` to show paywall early
2. **Server-side enforcement** (authoritative): Call Cloud Function for actual creation
3. **Security Rules** (guardrails): Block direct client writes to quota'd collections

Client-side checks are UX only. Server-side enforcement is required.

## Testing

### Test Auth Flow

1. Start emulators
2. Use Emulator UI to create test users
3. Sign in/up in app
4. Verify user appears in Emulator UI

### Test Quota Enforcement

1. Create objects via `createWithQuota` function
2. Check quota counters in Firestore (`users/{uid}/quota/{objectKey}`)
3. Exceed free limit, verify `resource-exhausted` error
4. Upgrade to Pro (mock in RevenueCat), verify unlimited access

### Reset Emulator Data

- Use Emulator UI "Reset" button
- Or restart emulators: `firebase emulators:start`
