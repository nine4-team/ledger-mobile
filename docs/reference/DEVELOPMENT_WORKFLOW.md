# Development Workflow

This guide covers the daily development workflow and common commands for working on the Ledger mobile app.

## Daily Development

### Starting Development (Most Common)

```bash
npm start
```

This command:
- Starts the Metro bundler
- Auto-connects to the app if already installed on simulator
- Enables hot refresh for JS/React changes
- Press `i` to open iOS simulator if needed
- Press `a` to open Android emulator if needed

---

## When to Rebuild

You only need to rebuild the native app when you:
- Add or remove **native modules** (e.g., a new Firebase package)
- Change **app.json** plugins
- Update native configuration (iOS/Android settings)
- Clear the app from your simulator/device

### Rebuild Commands

**iOS:**
```bash
npx expo run:ios
```

**Android:**
```bash
npx expo run:android
```

**Both platforms:**
```bash
npx expo prebuild --clean
npx expo run:ios
npx expo run:android
```

---

## Quick Reference

| Scenario | Command |
|----------|---------|
| **Daily coding** | `npm start` |
| **Added native dependency** | `npx expo run:ios` or `npx expo run:android` |
| **Clear Metro cache** | `npm start -- --clear` |
| **Run on physical device** | `npm run ios:device` |
| **Build release version** | `npm run ios:release` or `npm run android:release` |
| **Regenerate native folders** | `npx expo prebuild --clean` |

---

## Development Features

### What Works
✅ Firebase native modules (offline support, real-time sync)
✅ Hot refresh for code changes
✅ Fast development iteration
✅ React Native Fast Refresh

### Hot Reload
- **JS/React changes**: Auto-reload on save
- **Native changes**: Requires rebuild with `npx expo run:ios/android`
- **Manual reload**: Shake device/simulator → "Reload"

---

## Troubleshooting

### Metro bundler won't start
```bash
# Clear watchman
watchman watch-del-all

# Clear Metro cache
npm start -- --clear
```

### App won't connect to Metro
```bash
# Restart Metro
# Kill all node processes, then:
npm start
```

### Changes not appearing
1. Try manual reload: Shake device → "Reload"
2. Clear cache: `npm start -- --clear`
3. Rebuild if native changes: `npx expo run:ios`

### Pod install failures (iOS)
```bash
cd ios
pod deintegrate
pod install
cd ..
```

---

## Project Structure Notes

- **No expo-dev-client**: Removed due to React Native 0.76.9 compatibility issues
- **Firebase setup**: Native-first using @react-native-firebase/* packages
- **Expo SDK**: Version 52.0.0
- **React Native**: Version 0.76.9
- **New Architecture**: Disabled (`newArchEnabled: false`)

---

## Related Documentation

- [Emulator Setup](./EMULATOR_SETUP.md) - Firebase emulator configuration
- [Testing Offline Mode](./TESTING_OFFLINE_MODE.md) - Offline functionality testing
