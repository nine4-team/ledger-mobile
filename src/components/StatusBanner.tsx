import React, { ReactNode, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { useTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';

export const STATUS_BANNER_HEIGHT = 32;

const ERROR_COLOR = '#b94520'; // Matches "Needs Review" badge color

type StatusBannerProps = {
  bottomOffset?: number;
  message: string;
  variant?: 'error' | 'warning' | 'info';
  actions?: ReactNode;
};

export const StatusBanner: React.FC<StatusBannerProps> = ({
  bottomOffset = 0,
  message,
  variant = 'info',
  actions,
}) => {
  const theme = useTheme();

  const themed = useMemo(
    () =>
      StyleSheet.create({
        banner: {
          backgroundColor: theme.colors.background,
          borderColor: theme.colors.border,
          bottom: bottomOffset,
        },
        text: {
          color: variant === 'error' ? ERROR_COLOR : theme.colors.text,
        },
      }),
    [bottomOffset, variant, theme]
  );

  return (
    <View style={[styles.banner, themed.banner]} accessibilityRole="text">
      <AppText variant="caption" style={[styles.text, themed.text]} numberOfLines={1}>
        {message}
      </AppText>
      {actions && <View style={styles.actions}>{actions}</View>}
    </View>
  );
};

const styles = StyleSheet.create({
  banner: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 6,
    paddingHorizontal: 12,
    borderTopWidth: 1,
    zIndex: 20,
    minHeight: STATUS_BANNER_HEIGHT,
  },
  text: {
    flex: 1,
    fontWeight: '500',
    textAlign: 'center',
  },
  actions: {
    flexDirection: 'row',
    gap: 16,
    marginLeft: 12,
  },
});
