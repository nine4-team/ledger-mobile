import React, { useState } from 'react';
import { Pressable, StyleSheet } from 'react-native';

import { triggerManualSync } from '../sync/syncActions';
import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export const RetrySyncButton: React.FC = () => {
  const theme = useTheme();
  const [isBusy, setIsBusy] = useState(false);

  const onPress = async () => {
    if (isBusy) return;
    setIsBusy(true);
    try {
      await triggerManualSync();
    } finally {
      setIsBusy(false);
    }
  };

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        {
          borderColor: theme.colors.border,
          backgroundColor: pressed ? theme.colors.border : theme.colors.background,
        },
      ]}
      accessibilityRole="button"
      accessibilityLabel="Retry sync"
    >
      <AppText variant="caption" style={{ color: theme.colors.text }}>
        {isBusy ? 'Retrying…' : 'Retry sync'}
      </AppText>
    </Pressable>
  );
};

const styles = StyleSheet.create({
  button: {
    borderRadius: 999,
    borderWidth: 1,
    paddingHorizontal: 10,
    paddingVertical: 6,
  },
});
