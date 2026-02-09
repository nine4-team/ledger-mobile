import React from 'react';
import { View, type ViewStyle } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING, getCardStyle } from '../ui';

type CardProps = {
  children: React.ReactNode;
  padding?: number;
  style?: ViewStyle;
};

export function Card({ children, padding = CARD_PADDING, style }: CardProps) {
  const uiKitTheme = useUIKitTheme();

  return <View style={[getCardStyle(uiKitTheme, { padding }), style]}>{children}</View>;
}
