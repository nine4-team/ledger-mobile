import React, { useMemo } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';

import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { useOfflineUXStore } from '../offline/offlineUxStore';

export interface OfflineLoadingOverlayProps {
  visible?: boolean;
  message?: string;
}

export const OfflineLoadingOverlay: React.FC<OfflineLoadingOverlayProps> = ({
  visible,
  message,
}) => {
  const theme = useTheme();
  const { isLoading, loadingMessage } = useOfflineUXStore();
  const show = typeof visible === 'boolean' ? visible : isLoading;
  const label = message ?? loadingMessage ?? 'Loading...';

  const themed = useMemo(
    () =>
      StyleSheet.create({
        overlay: {
          backgroundColor: 'rgba(0, 0, 0, 0.25)',
        },
        card: {
          backgroundColor: theme.colors.background,
          borderColor: theme.colors.border,
        },
        text: {
          color: theme.colors.textSecondary,
        },
        spinner: {
          color: theme.colors.primary,
        },
      }),
    [theme]
  );

  if (!show) {
    return null;
  }

  return (
    <View style={[styles.overlay, themed.overlay]} pointerEvents="auto">
      <View style={[styles.card, themed.card]}>
        <ActivityIndicator size="large" color={themed.spinner.color} />
        <AppText variant="body" style={[styles.cardText, themed.text]}>
          {label}
        </AppText>
      </View>
    </View>
  );
};

export interface StaleIndicatorProps {
  visible?: boolean;
  label?: string;
}

export const StaleIndicator: React.FC<StaleIndicatorProps> = ({ visible, label }) => {
  const theme = useTheme();
  const { isStale, staleMessage } = useOfflineUXStore();
  const show = typeof visible === 'boolean' ? visible : isStale;
  const text = label ?? staleMessage ?? 'Stale';

  const themed = useMemo(
    () =>
      StyleSheet.create({
        badge: {
          backgroundColor: theme.colors.background,
          borderColor: theme.colors.border,
        },
        text: {
          color: theme.colors.textSecondary,
        },
      }),
    [theme]
  );

  if (!show) {
    return null;
  }

  return (
    <View style={[styles.badge, themed.badge]} accessibilityRole="text">
      <AppText variant="caption" style={[styles.badgeText, themed.text]}>
        {text}
      </AppText>
    </View>
  );
};

export interface QueuedWritesBadgeProps {
  count?: number;
  label?: string;
  showZero?: boolean;
}

export const QueuedWritesBadge: React.FC<QueuedWritesBadgeProps> = ({
  count,
  label,
  showZero = false,
}) => {
  const theme = useTheme();
  const { queuedWritesCount } = useOfflineUXStore();
  const value = typeof count === 'number' ? count : queuedWritesCount;
  const show = showZero ? value >= 0 : value > 0;
  const text = label ?? `Queued ${value}`;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        badge: {
          backgroundColor: theme.colors.background,
          borderColor: theme.colors.border,
        },
        text: {
          color: theme.colors.textSecondary,
        },
      }),
    [theme]
  );

  if (!show) {
    return null;
  }

  return (
    <View style={[styles.badge, themed.badge]} accessibilityRole="text">
      <AppText variant="caption" style={[styles.badgeText, themed.text]}>
        {text}
      </AppText>
    </View>
  );
};

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
  },
  card: {
    borderWidth: 1,
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    gap: 10,
    minWidth: 180,
  },
  cardText: {
    textAlign: 'center',
  },
  badge: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 4,
    alignSelf: 'flex-start',
  },
  badgeText: {
    fontWeight: '600',
  },
});
