import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { useNetworkStatus } from '../hooks/useNetworkStatus';
import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export const NetworkStatusBanner: React.FC = () => {
  const { isOnline, isSlowConnection } = useNetworkStatus();
  const theme = useTheme();

  const showOffline = !isOnline;
  const showSlow = isOnline && isSlowConnection;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        banner: {
          backgroundColor: showOffline ? theme.colors.error : theme.colors.background,
          borderColor: theme.colors.border,
        },
        text: {
          color: showOffline ? theme.colors.background : theme.colors.text,
        },
      }),
    [isOnline, isSlowConnection, showOffline, theme]
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
    top: 0,
    left: 0,
    right: 0,
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderBottomWidth: 1,
    zIndex: 20,
  },
  text: {
    textAlign: 'center',
    fontWeight: '600',
  },
});
