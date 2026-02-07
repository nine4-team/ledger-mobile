import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React from 'react';
import { StyleSheet, View } from 'react-native';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { useTheme } from '../theme/ThemeProvider';

export type ErrorRetryViewProps = {
  message: string;
  onRetry?: () => void;
  isOffline?: boolean;
};

export function ErrorRetryView({ message, onRetry, isOffline = false }: ErrorRetryViewProps) {
  const theme = useTheme();

  return (
    <View style={styles.container} accessibilityRole="alert">
      <MaterialIcons
        name={isOffline ? 'cloud-off' : 'error-outline'}
        size={48}
        color={theme.colors.error}
      />
      <AppText variant="body" style={[styles.message, { color: theme.colors.textSecondary }]}>
        {message}
      </AppText>
      {onRetry && (
        <AppButton
          title="Retry"
          onPress={onRetry}
          variant="secondary"
          accessibilityLabel="Retry loading"
          accessibilityHint="Tap to try loading again"
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    paddingVertical: 32,
    paddingHorizontal: 24,
  },
  message: {
    textAlign: 'center',
  },
});
