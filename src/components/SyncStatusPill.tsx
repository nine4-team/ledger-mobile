import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { useSyncStatusStore } from '../sync/syncStatusStore';
import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { RetrySyncButton } from './RetrySyncButton';

export const SyncStatusPill: React.FC = () => {
  const theme = useTheme();
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
  const [expanded, setExpanded] = useState(false);

  const totalPending = pendingWritesCount + pendingRequestDocs + pendingUploads;
  const totalFailed = failedRequestDocs + failedUploads;

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
  const show = statusVariant !== 'idle';
  const message = useMemo(() => {
    if (statusVariant === 'error') {
      return `Sync error: ${lastError ?? 'Some changes could not sync.'}`;
    }
    if (statusVariant === 'syncing') {
      return 'Syncing changes…';
    }
    if (statusVariant === 'waiting') {
      return "Changes will sync when you're back online";
    }
    if (totalPending > 0) {
      return totalPending === 1 ? '1 change pending' : `${totalPending} changes pending`;
    }
    return '';
  }, [isOnline, lastError, statusVariant, totalPending]);

  const themed = useMemo(
    () =>
      StyleSheet.create({
        pill: {
          borderColor: theme.colors.border,
          backgroundColor: theme.colors.background,
        },
        error: {
          borderColor: theme.colors.error,
        },
        text: {
          color: theme.colors.text,
        },
        errorText: {
          color: theme.colors.error,
        },
      }),
    [theme]
  );

  if (!show) {
    return null;
  }

  return (
    <View style={styles.wrapper} pointerEvents="box-none">
      <Pressable
        style={[
          styles.pill,
          themed.pill,
          statusVariant === 'error' && themed.error,
          expanded && styles.pillExpanded,
        ]}
        onPress={() => setExpanded((prev) => !prev)}
        accessibilityRole="button"
        accessibilityLabel="Sync status"
      >
        <AppText
          variant="caption"
          style={[styles.text, themed.text, statusVariant === 'error' && themed.errorText]}
        >
          {message}
        </AppText>
        {expanded && statusVariant === 'error' && (
          <View style={styles.retry}>
            <RetrySyncButton />
          </View>
        )}
      </Pressable>
    </View>
  );
};

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    right: 12,
    bottom: 24,
    zIndex: 30,
    alignItems: 'flex-end',
  },
  pill: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
    maxWidth: 260,
  },
  pillExpanded: {
    gap: 8,
  },
  text: {
    textAlign: 'center',
  },
  retry: {
    alignItems: 'flex-end',
  },
});
