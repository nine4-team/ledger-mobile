import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

type NetworkStatusBannerProps = {
  bottomOffset?: number;
};

export const NetworkStatusBanner: React.FC<NetworkStatusBannerProps> = ({ bottomOffset = 0 }) => {
  const { isOnline, isSlowConnection } = useNetworkStatus();
  const theme = useTheme();

  const showOffline = !isOnline;
  const showSlow = isOnline && isSlowConnection;

  // DEBUG: Log banner state
  console.log('📱 NetworkStatusBanner: Render', { isOnline, isSlowConnection, showOffline, showSlow });

  const themed = useMemo(
    () =>
      StyleSheet.create({
        banner: {
          backgroundColor: showOffline ? theme.colors.error : theme.colors.background,
          borderColor: theme.colors.border,
          bottom: bottomOffset,
        },
        text: {
          color: showOffline ? theme.colors.background : theme.colors.text,
        },
      }),
    [bottomOffset, isOnline, isSlowConnection, showOffline, theme]
  );

  if (!showOffline && !showSlow) {
    return null;
  }

  const label = showOffline
    ? 'Offline - Changes will sync when reconnected'
    : 'Slow connection detected';

  return (
    <View style={[styles.banner, themed.banner]} accessibilityRole="text">
      <AppText variant="caption" style={[styles.text, themed.text]}>
        {label}
      </AppText>
    </View>
  );
};

const styles = StyleSheet.create({
  banner: {
    position: 'absolute',
    left: 0,
    right: 0,
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderTopWidth: 1,
    zIndex: 20,
  },
  text: {
    textAlign: 'center',
    fontWeight: '600',
  },
});
