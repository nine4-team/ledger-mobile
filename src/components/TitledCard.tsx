import React from 'react';
import { StyleSheet, View, type ViewStyle } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { CARD_PADDING, getCardStyle, getTextSecondaryStyle, textEmphasis } from '../ui';

type TitledCardProps = {
  title: string;
  children: React.ReactNode;
  cardPadding?: number;
  containerStyle?: ViewStyle;
  cardStyle?: ViewStyle;
  titleStyle?: ViewStyle;
};

export function TitledCard({
  title,
  children,
  cardPadding = CARD_PADDING,
  containerStyle,
  cardStyle,
  titleStyle,
}: TitledCardProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={containerStyle}>
      <AppText
        variant="caption"
        style={[styles.title, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme), titleStyle]}
      >
        {title}
      </AppText>
      <View style={[getCardStyle(uiKitTheme, { padding: cardPadding }), cardStyle]}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  title: {
    marginBottom: 8,
  },
});
