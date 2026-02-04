import React, { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { useSyncStatusStore } from '../sync/syncStatusStore';
import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export const BackgroundSyncErrorNotifier: React.FC = () => {
  const theme = useTheme();
  const { backgroundError, clearBackgroundError } = useSyncStatusStore();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!backgroundError) {
      setVisible(false);
      return;
    }
    setVisible(true);
    const timeout = setTimeout(() => {
      setVisible(false);
      clearBackgroundError();
    }, 5000);
    return () => clearTimeout(timeout);
  }, [backgroundError, clearBackgroundError]);

  if (!backgroundError || !visible) {
    return null;
  }

  return (
    <View style={[styles.toast, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}>
      <AppText
        variant="caption"
        style={{ color: backgroundError.isOffline ? theme.colors.textSecondary : theme.colors.error }}
      >
        {backgroundError.message}
      </AppText>
    </View>
  );
};

const styles = StyleSheet.create({
  toast: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: 88,
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 10,
    zIndex: 40,
  },
});
