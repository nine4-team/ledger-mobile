# Running iOS Simulator for UI Component Dev

This repo is an **Expo + React Native** app using **native Firebase modules** (`@react-native-firebase/*`).

- **Expo Go is not supported** (native modules).
- You **can** run the UI **without Firebase/RevenueCat env configured**. In dev, auth is automatically bypassed when Firebase isn’t configured.

## Goal: “Just run the simulator to dev UI components”

You want:
- iOS Simulator app installed once (a “dev client” / native build)
- Metro running in **dev-client** mode
- No `.env` required for basic UI navigation

## Prereqs

- Node + npm
- Xcode installed (for iOS simulator)
- Dependencies installed:

```bash
npm install
```

## First-time (or after native dependency changes)

1) Generate native projects (creates/updates `ios/` + `android/`):

```bash
npx expo prebuild
```

2) Build + install the app into the iOS Simulator:

```bash
npx expo run:ios
```

3) Start Metro in dev-client mode:

```bash
npx expo start --dev-client
```

From the Metro UI/terminal prompt, open iOS (usually press `i`).

## Day-to-day loop (UI work)

If the app is already installed in the simulator, you usually only need:

```bash
npx expo start --dev-client
```

If you uninstalled the app from the simulator, or native bits changed, rerun:

```bash
npx expo run:ios
```

## No `.env`? What works vs what doesn’t

**Works (UI dev):**
- Navigation and screens load
- UI components can be developed/styled
- Auth gate is bypassed automatically in dev when Firebase isn’t configured

**Doesn’t work (until configured):**
- Firebase Auth sign-in/sign-up
- Firestore reads/writes
- Any code path that requires a real Firebase project

RevenueCat is also optional: if `EXPO_PUBLIC_REVENUECAT_API_KEY` is missing, it logs a warning and continues.

## Troubleshooting

- **Stuck on loading / can’t open iOS**:
  - Make sure you’re using `npx expo start --dev-client` (not plain `expo start`).
  - Reinstall the simulator app: `npx expo run:ios`.

- **Firebase errors while just trying to view UI**:
  - Ensure you haven’t forced auth on: unset `EXPO_PUBLIC_BYPASS_AUTH=false` if you set it manually.
  - For pure UI work, leave Firebase unconfigured and let dev bypass kick in.

## About `npm audit` vulnerabilities

- Prefer:

```bash
npm audit
npm audit fix
```

- Avoid `npm audit fix --force` unless you’ve reviewed the changes. In Expo/React Native projects, forced fixes can jump major versions and break compatibility.

