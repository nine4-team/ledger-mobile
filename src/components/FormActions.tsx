import React from 'react';
import { StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../theme/ThemeProvider';

interface FormActionsProps {
  children: React.ReactNode;
}

/**
 * A sticky footer bar for form cancel/save buttons.
 * Position as a sibling below a ScrollView so it stays pinned at the bottom.
 *
 * Callers should pass `style={{ flex: 1 }}` on each AppButton for equal width.
 *
 * @example
 * ```tsx
 * <AppScrollView style={{ flex: 1 }}>
 *   {/* form fields *\/}
 * </AppScrollView>
 * <FormActions>
 *   <AppButton title="Cancel" variant="secondary" style={{ flex: 1 }} />
 *   <AppButton title="Save" style={{ flex: 1 }} />
 * </FormActions>
 * ```
 */
export function FormActions({ children }: FormActionsProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: theme.colors.background,
          borderTopColor: theme.colors.border,
          paddingBottom: Math.max(16, insets.bottom),
        },
      ]}
    >
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    gap: 12,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
});
