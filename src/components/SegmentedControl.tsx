import React, { useMemo } from 'react';
import { Pressable, StyleSheet, View, ViewStyle } from 'react-native';
import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';

export type SegmentedControlOption<T extends string> = {
  value: T;
  label: string;
  icon?: React.ReactNode;
  accessibilityLabel?: string;
};

type Props<T extends string> = {
  value: T;
  options: readonly SegmentedControlOption<T>[];
  onChange: (next: T) => void;
  accessibilityLabel?: string;
  style?: ViewStyle;
};

export function SegmentedControl<T extends string>({
  value,
  options,
  onChange,
  accessibilityLabel,
  style,
}: Props<T>) {
  const uiKitTheme = useUIKitTheme();
  const themed = useMemo(
    () =>
      StyleSheet.create({
        container: {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.screen,
        },
        segmentDivider: {
          borderRightWidth: StyleSheet.hairlineWidth,
          borderRightColor: uiKitTheme.border.primary,
        },
        segmentSelected: {
          backgroundColor: uiKitTheme.background.surface,
        },
        segmentPressed: {
          opacity: 0.75,
        },
        labelSelected: {
          fontWeight: '700',
          color: uiKitTheme.text.primary,
        },
        labelUnselected: {
          fontWeight: '600',
          color: uiKitTheme.text.secondary,
        },
      }),
    [uiKitTheme]
  );

  return (
    <View
      accessibilityRole="tablist"
      accessibilityLabel={accessibilityLabel}
      style={[styles.container, themed.container, style]}
    >
      {options.map((opt, idx) => {
        const selected = opt.value === value;
        const isFirst = idx === 0;
        const isLast = idx === options.length - 1;

        return (
          <Pressable
            key={opt.value}
            accessibilityRole="tab"
            accessibilityLabel={opt.accessibilityLabel ?? opt.label}
            accessibilityState={{ selected }}
            onPress={() => onChange(opt.value)}
            style={({ pressed }) => [
              styles.segment,
              !isLast && themed.segmentDivider,
              isFirst && styles.first,
              isLast && styles.last,
              selected && themed.segmentSelected,
              pressed && !selected && themed.segmentPressed,
            ]}
          >
            <View style={styles.content}>
              {opt.icon ? <View style={styles.icon}>{opt.icon}</View> : null}
              <AppText variant="caption" style={selected ? themed.labelSelected : themed.labelUnselected}>
                {opt.label}
              </AppText>
            </View>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    borderWidth: 1,
    borderRadius: 12,
    overflow: 'hidden',
  },
  segment: {
    flex: 1,
    paddingVertical: 10,
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  icon: {
    marginRight: 6,
  },
  first: {},
  last: {},
});

