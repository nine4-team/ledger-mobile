import NetInfo, { NetInfoState } from '@react-native-community/netinfo';
import { useState, useEffect, useRef } from 'react';
import { AppState } from 'react-native';

import { checkFirebaseHealth } from '../utils/healthCheck';

export interface NetworkStatus {
  isOnline: boolean;
  isSlowConnection: boolean;
  lastOnline?: number;
  lastOfflineReason?: string;
  isHealthy?: boolean; // App-specific health check result
}

/**
 * Debounce/grace period configuration.
 *
 * These timing constants prevent banner flicker on brief network blips:
 * - T_OFFLINE_MS: How long we wait before confirming "offline" state (10 seconds)
 * - T_ONLINE_MS: How long we wait before confirming "online" state (2 seconds)
 *
 * Per OFFLINE_CAPABILITY_SPEC.md lines 129-142:
 * - Offline confirmation delay: 5-15s (we use 10s)
 * - Online confirmation delay: 1-3s (we use 2s)
 */
const T_OFFLINE_MS = 10_000; // 10 seconds - grace period before showing offline
const T_ONLINE_MS = 2_000;   // 2 seconds - grace period before clearing offline

/**
 * Health check configuration.
 *
 * Per OFFLINE_CAPABILITY_SPEC.md lines 111-127:
 * - Health check verifies Firebase is reachable, not just generic internet
 * - Runs periodically when app is active
 * - Non-blocking, never delays UI render
 *
 * We run more frequently (15s) to catch flaky network recoveries faster.
 */

/**
 * Hook to monitor network connectivity status with debouncing.
 *
 * State machine:
 * 1. NetInfo emits raw connectivity signal (rawOnline)
 * 2. Debounce logic applies grace periods based on state transitions
 * 3. App-specific health check verifies Firebase connectivity
 * 4. Combined signal (isOnline) is exposed to UI
 *
 * Prevents banner flicker on brief network blips:
 * - Brief offline blips (< 10s) don't trigger offline banner
 * - Quick return to online (after ~2s) clears offline banner
 * - Sustained offline (>= 10s) shows offline banner
 *
 * Uses NetInfo for React Native platform reachability + Firebase health check.
 */
export function useNetworkStatus(): NetworkStatus {
  // Debounced state (exposed to UI)
  const [isOnline, setIsOnline] = useState(true);
  const [isSlowConnection, setIsSlowConnection] = useState(false);
  const [lastOnline, setLastOnline] = useState<number | undefined>(() => Date.now());
  const [lastOfflineReason, setLastOfflineReason] = useState<string | undefined>();
  const [isHealthy, setIsHealthy] = useState<boolean>(true);

  // DEBUG: Verify hook is mounting
  useEffect(() => {
    console.log('🔌 useNetworkStatus: Hook mounted');
    return () => console.log('🔌 useNetworkStatus: Hook unmounted');
  }, []);

  // Raw signal tracking (internal)
  const rawOnlineRef = useRef<boolean>(true);
  const pendingTimerRef = useRef<NodeJS.Timeout | null>(null);
  const healthCheckIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Health check effect - runs periodically when app is active
  useEffect(() => {
    const runHealthCheck = async () => {
      const healthy = await checkFirebaseHealth();
      setIsHealthy(healthy);
    };

    // Run initial health check (non-blocking)
    runHealthCheck().catch((err) => {
      console.warn('[useNetworkStatus] Initial health check failed:', err);
      setIsHealthy(false);
    });

    // Set up periodic health check
    healthCheckIntervalRef.current = setInterval(() => {
      runHealthCheck().catch((err) => {
        console.warn('[useNetworkStatus] Periodic health check failed:', err);
        setIsHealthy(false);
      });
    }, 60_000); // 1 minute

    // Cleanup: clear health check interval
    return () => {
      if (healthCheckIntervalRef.current) {
        clearInterval(healthCheckIntervalRef.current);
        healthCheckIntervalRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    /**
     * Process raw connectivity state change with debouncing.
     *
     * State transitions:
     * - rawOnline=true, debouncedOnline=true: Already online, no timer needed
     * - rawOnline=false, debouncedOnline=true: Start T_OFFLINE_MS timer to go offline
     * - rawOnline=true, debouncedOnline=false: Start T_ONLINE_MS timer to go online
     * - rawOnline=false, debouncedOnline=false: Already offline, no timer needed
     *
     * IMPORTANT: NetInfo's event listener doesn't always fire reliably when
     * network state changes (especially WiFi on -> off -> on). We compensate
     * with periodic polling and AppState-based refresh (see below).
     */
    const processNetworkChange = (state: NetInfoState) => {
      // Be optimistic: if connected to network, treat as potentially online.
      // NetInfo's isInternetReachable can lag significantly after reconnecting,
      // causing the offline banner to stick. We rely on the health check +
      // debounce to verify actual connectivity instead.
      const rawOnline = state.isConnected ?? false;

      // DEBUG: Log network state changes
      console.log('🔌 useNetworkStatus: Network change detected', {
        isConnected: state.isConnected,
        type: state.type,
        rawOnline,
        currentIsOnline: isOnline
      });

      // Update raw signal
      rawOnlineRef.current = rawOnline;

      // Determine slow connection based on connection type
      // Consider 2g/3g as slow, 4g/5g/wifi as fast
      const slow =
        state.type === 'cellular' &&
        (state.details?.cellularGeneration === '2g' ||
          state.details?.cellularGeneration === '3g');
      setIsSlowConnection(slow);

      // Clear any existing pending timer
      if (pendingTimerRef.current) {
        clearTimeout(pendingTimerRef.current);
        pendingTimerRef.current = null;
      }

      // Apply debounce logic based on current debounced state
      setIsOnline((currentDebouncedOnline) => {
        if (rawOnline === currentDebouncedOnline) {
          // Raw and debounced states match - no transition needed
          if (rawOnline) {
            // We're online, update lastOnline immediately
            setLastOnline(Date.now());
            setLastOfflineReason(undefined);
          }
          return currentDebouncedOnline;
        }

        // States differ - need to schedule transition
        if (rawOnline && !currentDebouncedOnline) {
          // Raw is online, but we're showing offline -> schedule online transition
          pendingTimerRef.current = setTimeout(() => {
            // Double-check raw state hasn't flipped again
            if (rawOnlineRef.current) {
              setIsOnline(true);
              setLastOnline(Date.now());
              setLastOfflineReason(undefined);
            }
            pendingTimerRef.current = null;
          }, T_ONLINE_MS);

          // Keep showing offline during grace period
          return currentDebouncedOnline;
        } else if (!rawOnline && currentDebouncedOnline) {
          // Raw is offline, but we're showing online -> schedule offline transition
          pendingTimerRef.current = setTimeout(() => {
            // Double-check raw state hasn't flipped again
            if (!rawOnlineRef.current) {
              setIsOnline(false);
              setLastOfflineReason(state.type ?? 'unknown');
            }
            pendingTimerRef.current = null;
          }, T_OFFLINE_MS);

          // Keep showing online during grace period
          return currentDebouncedOnline;
        }

        // Should not reach here, but return current state as fallback
        return currentDebouncedOnline;
      });
    };

    // Subscribe to network state changes
    const unsubscribe = NetInfo.addEventListener(processNetworkChange);

    // Get initial state
    NetInfo.fetch().then(processNetworkChange);

    // WORKAROUND: NetInfo events don't always fire reliably (especially on iOS).
    // Poll periodically to catch missed state changes.
    const pollInterval = setInterval(() => {
      NetInfo.fetch().then(processNetworkChange);
    }, 3000); // Poll every 3 seconds

    // WORKAROUND: Force NetInfo refresh when app comes to foreground.
    // This catches state changes that happened while the app was backgrounded.
    const appStateSubscription = AppState.addEventListener('change', (nextAppState) => {
      if (nextAppState === 'active') {
        NetInfo.fetch().then(processNetworkChange);
      }
    });

    // Cleanup: clear pending timer, polling, and unsubscribe
    return () => {
      if (pendingTimerRef.current) {
        clearTimeout(pendingTimerRef.current);
        pendingTimerRef.current = null;
      }
      clearInterval(pollInterval);
      appStateSubscription.remove();
      unsubscribe();
    };
  }, []);

  return { isOnline, isSlowConnection, lastOnline, lastOfflineReason, isHealthy };
}
