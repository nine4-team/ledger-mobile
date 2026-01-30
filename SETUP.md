# Setup Checklist

Use this checklist when setting up a new app from this template.

## Initial Setup

- [ ] Clone or use template
- [ ] Run `npm install`
- [ ] Copy `.env.example` to `.env`
- [ ] Fill in Firebase config in `.env`
- [ ] Fill in RevenueCat API key in `.env`

## Firebase Setup

- [ ] Create Firebase project at https://console.firebase.google.com
- [ ] Enable Authentication (Email/Password)
- [ ] Enable Firestore Database
- [ ] **Add native apps** (required for offline-ready support):
  - [ ] Add iOS app: Project Settings > General > Your apps > Add app > iOS
  - [ ] Add Android app: Project Settings > General > Your apps > Add app > Android
  - [ ] Download `GoogleService-Info.plist` (iOS) and `google-services.json` (Android)
  - [ ] Place both files in project root
- [ ] Get web config from Project Settings > General > Your apps > Web (for web platform support)
- [ ] Copy config values to `.env` as `EXPO_PUBLIC_FIREBASE_*`
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`
- [ ] Deploy Cloud Functions: `firebase deploy --only functions`

## RevenueCat Setup

- [ ] Create RevenueCat account at https://www.revenuecat.com
- [ ] Create new project
- [ ] Add iOS app (App Store Connect)
- [ ] Add Android app (Google Play Console)
- [ ] Create "pro" entitlement
- [ ] Create products/packages
- [ ] Get public API key
- [ ] Add to `.env` as `EXPO_PUBLIC_REVENUECAT_API_KEY`

## App Customization

- [ ] Edit `src/config/appConfig.ts`:
  - [ ] Change `appName`
  - [ ] Define quota types
  - [ ] Set `revenueCatEntitlementId`
- [ ] Customize theme in `src/theme/theme.ts`
- [ ] Update `app.json`:
  - [ ] App name, slug
  - [ ] Bundle identifiers
  - [ ] Icons (add to `assets/`)

## Development

- [ ] Install Firebase CLI: `npm install -g firebase-tools`
- [ ] Start emulators: `firebase emulators:start`
- [ ] **Install native Firebase config files** (required for native SDK):
  - [ ] Download `google-services.json` from Firebase Console → Project Settings → Your apps → Android app
  - [ ] Download `GoogleService-Info.plist` from Firebase Console → Project Settings → Your apps → iOS app
  - [ ] Place both files in project root (they will be automatically linked during build)
- [ ] **Build and install a dev client** (required - Expo Go not supported):
  - [ ] Install EAS CLI: `npm install -g eas-cli`
  - [ ] Configure EAS: `eas build:configure`
  - [ ] Build dev client: `eas build --profile development --platform ios` (and/or Android)
  - [ ] Install dev client on device/simulator
- [ ] **Generate native code** (required after installing native Firebase packages):
  - [ ] Run `npx expo prebuild` to generate native iOS/Android folders, OR
  - [ ] EAS build automatically runs prebuild during build
- [ ] Start Expo for dev client: `npm start` (then press `i` / scan QR into the dev client) or `npx expo start --dev-client`
- [ ] Test auth flow (sign up/in)
- [ ] Test quota system
- [ ] Test paywall (requires dev client)

## Build & Test

- [ ] Install EAS CLI: `npm install -g eas-cli`
- [ ] Configure EAS: `eas build:configure`
- [ ] Build dev client: `eas build --profile development --platform ios`
- [ ] Install dev client on device
- [ ] Test RevenueCat purchases
- [ ] Test quota enforcement

## Optional Features

- [ ] Install dictation widget (if needed)
- [ ] Implement offline-ready data layer (wire to native Firestore)
- [ ] Add custom screens/routes
- [ ] Customize UI components

## Deployment

- [ ] Update version in `app.json`
- [ ] Build production: `eas build --profile production --platform all`
- [ ] Submit to App Store / Play Store
- [ ] Deploy Firebase Functions: `firebase deploy --only functions`
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`

## Offline-ready + multi-doc correctness (request docs)

This skeleton’s offline story is **native-first**:

- **Firestore is canonical** (cached reads + queued offline writes via native SDK)
- **Scoped listeners only** (bounded to active scope; detach on background)
- **No outbox/sync engine** (SQLite is not the source of truth)

### Runtime requirements (React Native)

- Expo Go is **not supported** for offline-ready claims
- Use an **EAS dev client** / native build
- Ensure you have `google-services.json` (Android) + `GoogleService-Info.plist` (iOS)

### Multi-doc correctness: request-doc workflows

For any operation that updates **multiple docs** or enforces invariants:

1. Client writes a request doc with `status: "pending"` (works offline; will sync later)
2. Cloud Function processes it (typically a Firestore transaction)
3. Function updates request status to:
   - `applied` + `appliedAt`, or
   - `failed` + `errorCode`/`errorMessage`
4. UI subscribes to the request doc and shows pending/applied/failed + retry (retry = create a new request doc)

**Implemented scaffolding in this repo**

- **Cloud Functions**: `firebase/functions/src/index.ts`
  - Triggers:
    - `accounts/{accountId}/projects/{projectId}/requests/{requestId}`
    - `accounts/{accountId}/inventory/requests/{requestId}`
  - Handler registry: `requestHandlers[type] = async (...) => { ... }`
- **Rules**: `firebase/firestore.rules`
  - Clients can **create/read** request docs
  - Clients **cannot** update/delete or forge `status: applied|failed`
  - Tighten request **read** access to your membership model for real apps
- **Client helpers**: `src/data/requestDocs.ts`
  - `createRequestDoc(type, payload, scope) -> requestId`
  - `subscribeToRequest(scope, requestId, onChange) -> unsubscribe`
