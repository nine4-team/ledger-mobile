import React, { useMemo } from 'react';
import { View, TouchableOpacity, TouchableOpacityProps, StyleSheet, ActivityIndicator } from 'react-native';
import { AppText } from './AppText';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { BUTTON_BORDER_RADIUS } from '../ui';

interface AppButtonProps extends Omit<TouchableOpacityProps, 'style'> {
  title: string;
  variant?: 'primary' | 'secondary';
  loading?: boolean;
  leftIcon?: React.ReactNode;
  style?: TouchableOpacityProps['style'];
}

export const AppButton: React.FC<AppButtonProps> = ({
  title,
  variant = 'primary',
  loading = false,
  disabled,
  leftIcon,
  style,
  ...props
}) => {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const isPrimary = variant === 'primary';
  const themed = useMemo(
    () =>
      StyleSheet.create({
        padding: {
          paddingVertical: theme.spacing.md,
          paddingHorizontal: theme.spacing.lg,
        },
        primaryBg: {
          backgroundColor: uiKitTheme.button.primary.background,
        },
        secondaryBg: {
          backgroundColor: uiKitTheme.button.secondary.background,
          borderColor: uiKitTheme.border.primary,
        },
        primaryTextColor: {
          color: uiKitTheme.button.primary.text,
        },
        secondaryTextColor: {
          color: uiKitTheme.button.secondary.text,
        },
      }),
    [theme, uiKitTheme]
  );

  return (
    <TouchableOpacity
      style={[
        styles.button,
        themed.padding,
        isPrimary ? themed.primaryBg : styles.secondary,
        !isPrimary && themed.secondaryBg,
        (disabled || loading) && styles.disabled,
        style,
      ]}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? (
        <ActivityIndicator
          color={isPrimary ? uiKitTheme.button.primary.text : uiKitTheme.button.secondary.text}
        />
      ) : (
        <View style={styles.content}>
          {!!leftIcon && <View style={styles.leftIcon}>{leftIcon}</View>}
          <AppText
            variant="body"
            style={[
              isPrimary ? styles.primaryText : styles.secondaryText,
              isPrimary ? themed.primaryTextColor : themed.secondaryTextColor,
            ]}
          >
            {title}
          </AppText>
        </View>
      )}
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  button: {
    // Dynamic padding comes from theme adapter; applied inline.
    borderRadius: BUTTON_BORDER_RADIUS,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  leftIcon: {
    marginRight: 10,
  },
  secondary: {
    borderWidth: 1,
  },
  disabled: {
    opacity: 0.5,
  },
  primaryText: {
    fontWeight: '600',
  },
  secondaryText: {
    fontWeight: '600',
  },
});
