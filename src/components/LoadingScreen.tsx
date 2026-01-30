import React, { useMemo } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { Screen } from './Screen';
import { AppText } from './AppText';
import { useTheme } from '../theme/ThemeProvider';

export const LoadingScreen: React.FC = () => {
  const theme = useTheme();
  const themed = useMemo(
    () =>
      StyleSheet.create({
        content: {
          gap: theme.spacing.md,
        },
        text: {
          marginTop: theme.spacing.md,
        },
      }),
    [theme]
  );

  return (
    <Screen style={styles.container}>
      <View style={[styles.content, themed.content]}>
        <ActivityIndicator size="large" color={theme.colors.primary} />
        <AppText variant="body" style={themed.text}>
          Loading...
        </AppText>
      </View>
    </Screen>
  );
};

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    alignItems: 'center',
  },
});
