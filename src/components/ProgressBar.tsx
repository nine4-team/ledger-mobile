import React, { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { useThemeContext } from '../theme/ThemeProvider';

export type ProgressBarProps = {
  /** 0–100 percentage filled */
  percentage: number;
  /** Fill color */
  color: string;
  /** Optional track background color (defaults to theme-aware gray) */
  trackColor?: string;
  /** Bar height in pixels (default 8) */
  height?: number;
  /** Optional overflow indicator: percentage beyond 100% */
  overflowPercentage?: number;
  /** Overflow fill color */
  overflowColor?: string;
  style?: ViewStyle;
};

export function ProgressBar({
  percentage,
  color,
  trackColor,
  height = 8,
  overflowPercentage,
  overflowColor,
  style,
}: ProgressBarProps) {
  const { resolvedColorScheme } = useThemeContext();
  const isDark = resolvedColorScheme === 'dark';

  const defaultTrackColor = isDark ? '#3A3A3C' : '#E5E7EB';
  const displayPercentage = Math.min(Math.max(percentage, 0), 100);
  const displayOverflow = overflowPercentage
    ? Math.min(Math.max(overflowPercentage, 0), 100)
    : 0;

  const trackStyle = useMemo(
    () => ({
      height,
      backgroundColor: trackColor ?? defaultTrackColor,
    }),
    [height, trackColor, defaultTrackColor]
  );

  return (
    <View style={[styles.track, trackStyle, style]}>
      <View
        style={[
          styles.fill,
          {
            width: `${displayPercentage}%`,
            backgroundColor: color,
          },
        ]}
      />
      {displayOverflow > 0 && overflowColor && (
        <View
          style={[
            styles.overflow,
            {
              width: `${displayOverflow}%`,
              backgroundColor: overflowColor,
            },
          ]}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  track: {
    borderRadius: 9999,
    overflow: 'hidden',
    position: 'relative',
  },
  fill: {
    position: 'absolute',
    left: 0,
    top: 0,
    height: '100%',
    borderRadius: 9999,
  },
  overflow: {
    position: 'absolute',
    right: 0,
    top: 0,
    height: '100%',
    borderRadius: 9999,
  },
});
