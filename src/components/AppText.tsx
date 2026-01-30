import React from 'react';
import { Text, TextProps, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeProvider';

interface AppTextProps extends TextProps {
  variant?: 'h1' | 'h2' | 'body' | 'caption';
}

export const AppText: React.FC<AppTextProps> = ({
  variant = 'body',
  style,
  children,
  ...props
}) => {
  const theme = useTheme();

  const themedStyle = (() => {
    switch (variant) {
      case 'h1':
        return { ...theme.typography.h1, color: theme.colors.text };
      case 'h2':
        return { ...theme.typography.h2, color: theme.colors.text };
      case 'caption':
        return { ...theme.typography.caption, color: theme.colors.textSecondary };
      case 'body':
      default:
        return { ...theme.typography.body, color: theme.colors.text };
    }
  })();

  return (
    <Text style={[styles[variant], themedStyle, style]} {...props}>
      {children}
    </Text>
  );
};

const styles = StyleSheet.create({
  // NOTE: These are “base” styles; dynamic theme colors/typography are applied inline.
  h1: {},
  h2: {},
  body: {},
  caption: {},
});
