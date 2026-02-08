import React from 'react';

import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { StatusBanner } from './StatusBanner';

type NetworkStatusBannerProps = {
  bottomOffset?: number;
};

export const NetworkStatusBanner: React.FC<NetworkStatusBannerProps> = ({ bottomOffset = 0 }) => {
  const { isOnline, isSlowConnection } = useNetworkStatus();

  const showOffline = !isOnline;
  const showSlow = isOnline && isSlowConnection;

  if (!showOffline && !showSlow) {
    return null;
  }

  const message = showOffline
    ? 'Offline - Changes will sync when reconnected'
    : 'Slow connection detected';

  return <StatusBanner bottomOffset={bottomOffset} message={message} variant={showOffline ? 'error' : 'warning'} />;
};
