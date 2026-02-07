import React, { useEffect, useRef } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from './AppText';
import { useTheme } from '../theme/ThemeProvider';
import { useSyncStatusStore } from '../sync/syncStatusStore';

export type SyncIndicatorProps = {
  show?: boolean;
};

export function SyncIndicator({ show }: SyncIndicatorProps) {
  const theme = useTheme();
  const isSyncing = useSyncStatusStore((state) => state.isSyncing);
  const pendingWritesCount = useSyncStatusStore((state) => state.pendingWritesCount);
  const rotateAnim = useRef(new Animated.Value(0)).current;

  const shouldShow = show !== undefined ? show : isSyncing && pendingWritesCount > 0;

  useEffect(() => {
    if (shouldShow) {
      const rotation = Animated.loop(
        Animated.timing(rotateAnim, {
          toValue: 1,
          duration: 1000,
          useNativeDriver: true,
        })
      );
      rotation.start();
      return () => rotation.stop();
    }
  }, [shouldShow, rotateAnim]);

  if (!shouldShow) {
    return null;
  }

  const rotate = rotateAnim.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  return (
    <View
      style={[styles.container, { backgroundColor: theme.colors.primary + '1A' }]}
      accessibilityRole="progressbar"
      accessibilityLabel="Syncing changes"
    >
      <Animated.View style={{ transform: [{ rotate }] }}>
        <MaterialIcons name="sync" size={16} color={theme.colors.primary} />
      </Animated.View>
      <AppText variant="caption" style={{ color: theme.colors.primary }}>
        Syncing...
      </AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderRadius: 999,
    alignSelf: 'flex-start',
  },
});
