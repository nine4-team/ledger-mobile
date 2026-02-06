# Testing Offline Mode - Reference Guide

## Problem: Offline Banner Not Working in Development

### Root Cause

When running the app in **development mode** (`npm run ios`), the app maintains a connection to the **Metro bundler** (dev server). When WiFi is turned off:

1. Metro connection dies
2. JavaScript execution **freezes** (timers stop, events don't fire)
3. The app becomes unresponsive
4. Network detection hooks can't work because JS isn't running

**Result**: The offline banner never appears because `setInterval`, `setTimeout`, and NetInfo event listeners all stop working when Metro disconnects.

---

## Solution: Test Without Metro Dependency

To properly test offline functionality, you need to run the app in a way that **doesn't depend on Metro for JavaScript execution**.

### Option 1: iOS Release Build (Recommended)

Build a production/release version that bundles all JavaScript into the app:

```bash
npm run ios:release
```

This command runs: `expo run:ios --configuration Release`

**What it does:**
- Bundles all JavaScript into the app binary
- Runs without connecting to Metro
- JavaScript continues executing even when WiFi is off
- Perfect for testing true offline behavior

**Configuration Note:**

Since the app uses Firebase emulators on `localhost`, they won't be reachable in offline mode. You have two options:

**A. Enable Auth Bypass for Offline Testing** (Recommended for testing)

Temporarily modify `.env`:
```bash
EXPO_PUBLIC_BYPASS_AUTH=true
EXPO_PUBLIC_USE_FIREBASE_EMULATORS=false
```

Then build:
```bash
npm run ios:release
```

**B. Use Production Firebase**

Modify `.env`:
```bash
EXPO_PUBLIC_USE_FIREBASE_EMULATORS=false
```

Then build with production Firebase credentials:
```bash
npm run ios:release
```

---

### Option 2: Test on Real Device

Metro connection is more stable on real devices over USB:

```bash
npm run ios:device
```

This command runs: `expo run:ios --device`

**Requirements:**
- iPhone connected via USB
- Device unlocked and trusted
- Metro connection runs over USB (more resilient to WiFi changes)

**Advantages:**
- Faster than full production build
- Can still use hot reload
- More realistic testing environment

---

### Option 3: Android Release Build

For Android testing:

```bash
npm run android:release
```

This command runs: `expo run:android --variant release`

---

## Testing Procedure

### Step 1: Build and Launch

```bash
# Option A: Production build (recommended)
npm run ios:release

# Option B: Real device
npm run ios:device
```

### Step 2: Verify Logs Are Working

You should see in the console:
```
🔌 useNetworkStatus: Hook mounted
🔌 useNetworkStatus: Network change detected {"isConnected": true, "type": "wifi", "rawOnline": true, "currentIsOnline": true}
📱 NetworkStatusBanner: Render {"isOnline": true, "isSlowConnection": false, "showOffline": false, "showSlow": false}
```

These logs confirm:
- ✅ Hook is mounted and running
- ✅ Network monitoring is active
- ✅ Banner component is rendering

### Step 3: Test WiFi OFF

1. With app running, turn WiFi **OFF** (Settings → WiFi → Off)
2. Watch console logs - they should **continue appearing** (every 3 seconds)
3. Wait **10-13 seconds**

**Expected behavior:**
```
🔌 useNetworkStatus: Network change detected {"isConnected": false, "type": "none", "rawOnline": false, "currentIsOnline": true}
🔌 useNetworkStatus: Network change detected {"isConnected": false, "type": "none", "rawOnline": false, "currentIsOnline": true}
🔌 useNetworkStatus: Network change detected {"isConnected": false, "type": "none", "rawOnline": false, "currentIsOnline": true}
// ... after 10 seconds ...
📱 NetworkStatusBanner: Render {"isOnline": false, "isSlowConnection": false, "showOffline": true, "showSlow": false}
```

**Visual result:**
- Red banner appears at bottom of screen
- Text: "Offline - Changes will sync when reconnected"

### Step 4: Test WiFi ON

1. Turn WiFi back **ON**
2. Wait **2-5 seconds**

**Expected behavior:**
```
🔌 useNetworkStatus: Network change detected {"isConnected": true, "type": "wifi", "rawOnline": true, "currentIsOnline": false}
// ... after 2 seconds ...
📱 NetworkStatusBanner: Render {"isOnline": true, "isSlowConnection": false, "showOffline": false, "showSlow": false}
```

**Visual result:**
- Banner disappears

---

## Debug Logging

The following debug logs are currently active:

### Hook Mount/Unmount
**File:** `src/hooks/useNetworkStatus.ts:64-68`
```typescript
console.log('🔌 useNetworkStatus: Hook mounted');
```

### Network State Changes
**File:** `src/hooks/useNetworkStatus.ts:120-126`
```typescript
console.log('🔌 useNetworkStatus: Network change detected', {
  isConnected: state.isConnected,
  type: state.type,
  rawOnline,
  currentIsOnline: isOnline
});
```

### Banner Renders
**File:** `src/components/NetworkStatusBanner.tsx:19-20`
```typescript
console.log('📱 NetworkStatusBanner: Render', { isOnline, isSlowConnection, showOffline, showSlow });
```

**Note:** These debug logs can be removed once offline functionality is confirmed working.

---

## Timing Specifications

Per `docs/specs/OFFLINE_CAPABILITY_SPEC.md`:

| Event | Grace Period | Purpose |
|-------|--------------|---------|
| **Network → Offline** | 10 seconds | Prevent banner flicker on brief blips |
| **Offline → Network** | 2 seconds | Quick banner dismissal on reconnect |
| **Health Check** | 60 seconds | Periodic Firebase connectivity check |
| **NetInfo Polling** | 3 seconds | Workaround for unreliable event firing |

---

## Troubleshooting

### ❌ No Logs Appear at All

**Cause:** Hook is not mounting (component not rendering)

**Fix:**
1. Check if there's a JavaScript error preventing app load
2. Add a log at the top of `app/(tabs)/_layout.tsx` to verify file is executing
3. Verify `NetworkStatusBanner` is actually rendered (line 85 of layout file)

### ❌ Logs Stop When WiFi Turns Off

**Cause:** Still connected to Metro dev server

**Fix:**
- Use `npm run ios:release` instead of `npm run ios`
- Or use `npm run ios:device` with real iPhone

### ❌ Banner Never Appears But Logs Continue

**Cause:** State is not updating after debounce period

**Fix:**
1. Check if `isOnline` changes to `false` in logs after 10 seconds
2. Verify timer logic in `useNetworkStatus.ts:152-173`
3. Check if there are any React rendering issues

### ❌ Banner Appears Immediately (No 10s Delay)

**Cause:** Debounce logic not working

**Fix:**
1. Check `T_OFFLINE_MS` constant (should be 10000ms)
2. Verify `pendingTimerRef` is being set correctly
3. Check if timers are being cleared prematurely

### ❌ Banner Sticks After Reconnect

**Cause:** Online transition not triggering

**Fix:**
1. Check if `rawOnline` changes to `true` in logs
2. Verify 2-second online grace period timer is firing
3. Check NetInfo is reporting `isConnected: true`

---

## Architecture Notes

### Component Hierarchy

```
app/(tabs)/_layout.tsx
  └─ NetworkStatusBanner (line 85)
       └─ useNetworkStatus() hook (line 13)
            ├─ NetInfo.addEventListener()
            ├─ setInterval (3s polling)
            ├─ AppState.addEventListener()
            └─ checkFirebaseHealth() (60s interval)
```

### State Flow

```
NetInfo → processNetworkChange() → debounce logic → setIsOnline() → Banner re-renders
```

### Debounce State Machine

1. **Online → Offline**:
   - Raw signal goes `false`
   - Wait 10 seconds (grace period)
   - If still `false`, set `isOnline: false`
   - Banner appears

2. **Offline → Online**:
   - Raw signal goes `true`
   - Wait 2 seconds (grace period)
   - If still `true`, set `isOnline: true`
   - Banner disappears

---

## Related Files

- **Hook**: `src/hooks/useNetworkStatus.ts`
- **Banner**: `src/components/NetworkStatusBanner.tsx`
- **Layout**: `app/(tabs)/_layout.tsx`
- **Spec**: `docs/specs/OFFLINE_CAPABILITY_SPEC.md`
- **Health Check**: `src/utils/healthCheck.ts`

---

## Quick Reference Commands

```bash
# Development (Metro connected - won't work for offline testing)
npm run ios

# Production build (recommended for offline testing)
npm run ios:release

# Real device (faster alternative)
npm run ios:device

# Android production
npm run android:release

# Start Firebase emulators
./start-emulators.sh
```

---

## Success Criteria

- ✅ Banner appears within 10-13 seconds of WiFi turning off
- ✅ Banner shows red background with white text
- ✅ Text reads: "Offline - Changes will sync when reconnected"
- ✅ Banner clears within 2-5 seconds of WiFi turning back on
- ✅ Works reliably even with flaky WiFi
- ✅ JavaScript continues executing when offline (logs keep appearing)
- ✅ No banner flicker on brief network blips (< 10 seconds)

---

*Last Updated: 2026-02-06*
