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
  headerAction?: React.ReactNode;
};

export function TitledCard({
  title,
  children,
  cardPadding = CARD_PADDING,
  containerStyle,
  cardStyle,
  titleStyle,
  headerAction,
}: TitledCardProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <View style={containerStyle}>
      <View style={styles.header}>
        <AppText
          variant="caption"
          style={[styles.title, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme), titleStyle]}
        >
          {title}
        </AppText>
        {headerAction}
      </View>
      <View style={[getCardStyle(uiKitTheme, { padding: cardPadding }), cardStyle]}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  title: {
    flex: 1,
  },
});
