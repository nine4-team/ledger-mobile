import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable } from 'react-native';

import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { getTrackedRequestsSnapshot } from '../sync/requestDocTracker';
import { dismissAllSyncErrors, triggerManualSync } from '../sync/syncActions';
import { useSyncStatusStore } from '../sync/syncStatusStore';
import { AppText } from './AppText';
import { StatusBanner } from './StatusBanner';

export { STATUS_BANNER_HEIGHT as SYNC_BANNER_HEIGHT } from './StatusBanner';

const ERROR_COLOR = '#b94520'; // Matches "Needs Review" badge color

type SyncStatusBannerProps = {
  bottomOffset?: number;
};

export const SyncStatusBanner: React.FC<SyncStatusBannerProps> = ({ bottomOffset = 0 }) => {
  const { isOnline } = useNetworkStatus();
  const {
    pendingWritesCount,
    pendingRequestDocs,
    failedRequestDocs,
    pendingUploads,
    failedUploads,
    isSyncing,
    lastError,
  } = useSyncStatusStore();
  const [isRetrying, setIsRetrying] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const prevTotalPendingRef = useRef(0);

  const totalPending = pendingWritesCount + pendingRequestDocs + pendingUploads;
  const totalFailed = failedRequestDocs + failedUploads;

  // Re-show banner when new pending writes arrive after a dismiss
  useEffect(() => {
    if (totalPending > prevTotalPendingRef.current) {
      setDismissed(false);
    }
    prevTotalPendingRef.current = totalPending;
  }, [totalPending]);

  const statusVariant =
    totalFailed > 0 || lastError
      ? 'error'
      : isSyncing
        ? 'syncing'
        : totalPending > 0 && !isOnline
          ? 'waiting'
          : totalPending > 0
            ? 'queue'
            : 'idle';

  const show = statusVariant !== 'idle' && !dismissed;

  const message = useMemo(() => {
    if (statusVariant === 'error') {
      if (failedRequestDocs > 0) {
        const snapshot = getTrackedRequestsSnapshot();
        const failedRequests = snapshot.filter(
          (r) => r.status === 'failed' || r.status === 'denied',
        );

        if (failedRequests.length === 1) {
          return failedRequests[0].errorMessage?.trim() || 'An operation failed to sync.';
        }
        if (failedRequests.length > 1) {
          return `${failedRequests.length} operations failed. Tap Retry or Dismiss.`;
        }
      }
      return lastError ?? 'Some changes could not sync.';
    }
    if (statusVariant === 'syncing') return 'Syncing changes…';
    if (statusVariant === 'waiting') return "Changes will sync when you're back online";
    if (totalPending > 0) {
      return totalPending === 1 ? '1 change pending' : `${totalPending} changes pending`;
    }
    return '';
  }, [failedRequestDocs, lastError, statusVariant, totalPending]);

  const isError = statusVariant === 'error';

  if (!show) return null;

  const handleRetry = async () => {
    if (isRetrying) return;
    setIsRetrying(true);
    try {
      await triggerManualSync();
    } finally {
      setIsRetrying(false);
    }
  };

  const actions = isError ? (
    <>
      <Pressable onPress={handleRetry} hitSlop={8} accessibilityRole="button" accessibilityLabel="Retry sync">
        <AppText variant="caption" style={{ color: ERROR_COLOR, fontWeight: '600', textDecorationLine: 'underline' }}>
          {isRetrying ? 'Retrying…' : 'Retry'}
        </AppText>
      </Pressable>
      <Pressable onPress={dismissAllSyncErrors} hitSlop={8} accessibilityRole="button" accessibilityLabel="Dismiss sync error">
        <AppText variant="caption" style={{ color: ERROR_COLOR, fontWeight: '600', textDecorationLine: 'underline' }}>
          Dismiss
        </AppText>
      </Pressable>
    </>
  ) : (
    <Pressable onPress={() => setDismissed(true)} hitSlop={8} accessibilityRole="button" accessibilityLabel="Dismiss sync status">
      <AppText variant="caption" style={{ fontWeight: '600', opacity: 0.5 }}>✕</AppText>
    </Pressable>
  );

  return <StatusBanner bottomOffset={bottomOffset} message={message} variant={isError ? 'error' : 'info'} actions={actions} />;
};
