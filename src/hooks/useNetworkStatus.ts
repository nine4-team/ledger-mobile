import { useState, useEffect } from 'react';
import NetInfo, { NetInfoState } from '@react-native-community/netinfo';

export interface NetworkStatus {
  isOnline: boolean;
  isSlowConnection: boolean;
  lastOnline?: number;
  lastOfflineReason?: string;
}

/**
 * Hook to monitor network connectivity status.
 * Uses NetInfo for React Native platform reachability.
 */
export function useNetworkStatus(): NetworkStatus {
  const [isOnline, setIsOnline] = useState(true);
  const [isSlowConnection, setIsSlowConnection] = useState(false);
  const [lastOnline, setLastOnline] = useState<number | undefined>(Date.now());
  const [lastOfflineReason, setLastOfflineReason] = useState<string | undefined>();

  useEffect(() => {
    const unsubscribe = NetInfo.addEventListener((state: NetInfoState) => {
      // isInternetReachable is the best indicator of actual internet access
      // fallback to isConnected if isInternetReachable is null
      const online =
        state.isInternetReachable !== null
          ? state.isInternetReachable
          : state.isConnected ?? false;

      setIsOnline(online);
      if (online) {
        setLastOnline(Date.now());
        setLastOfflineReason(undefined);
      } else {
        setLastOfflineReason(state.type ?? 'unknown');
      }

      // Determine slow connection based on connection type
      // Consider 2g/3g as slow, 4g/5g/wifi as fast
      const slow =
        state.type === 'cellular' &&
        (state.details?.cellularGeneration === '2g' ||
          state.details?.cellularGeneration === '3g');
      setIsSlowConnection(slow);
    });

    // Get initial state
    NetInfo.fetch().then((state: NetInfoState) => {
      const online =
        state.isInternetReachable !== null
          ? state.isInternetReachable
          : state.isConnected ?? false;
      setIsOnline(online);
      if (online) {
        setLastOnline(Date.now());
        setLastOfflineReason(undefined);
      } else {
        setLastOfflineReason(state.type ?? 'unknown');
      }

      const slow =
        state.type === 'cellular' &&
        (state.details?.cellularGeneration === '2g' ||
          state.details?.cellularGeneration === '3g');
      setIsSlowConnection(slow);
    });

    return () => {
      unsubscribe();
    };
  }, []);

  return { isOnline, isSlowConnection, lastOnline, lastOfflineReason };
}
