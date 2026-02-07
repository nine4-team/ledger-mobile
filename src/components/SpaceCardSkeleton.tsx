import React, { useEffect, useRef } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import { useUIKitTheme } from '../theme/ThemeProvider';

export function SpaceCardSkeleton() {
  const uiKitTheme = useUIKitTheme();
  const shimmerAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const shimmer = Animated.loop(
      Animated.sequence([
        Animated.timing(shimmerAnim, {
          toValue: 1,
          duration: 1000,
          useNativeDriver: true,
        }),
        Animated.timing(shimmerAnim, {
          toValue: 0,
          duration: 1000,
          useNativeDriver: true,
        }),
      ])
    );
    shimmer.start();
    return () => shimmer.stop();
  }, [shimmerAnim]);

  const shimmerOpacity = shimmerAnim.interpolate({
    inputRange: [0, 1],
    outputRange: [0.3, 0.7],
  });

  return (
    <View
      style={[
        styles.card,
        {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.surface,
        },
      ]}
      accessibilityLabel="Loading space"
    >
      <Animated.View
        style={[
          styles.imageBox,
          {
            backgroundColor: uiKitTheme.background.tertiary,
            opacity: shimmerOpacity,
          },
        ]}
      />
      <View style={styles.content}>
        <Animated.View
          style={[
            styles.titleBox,
            {
              backgroundColor: uiKitTheme.background.tertiary,
              opacity: shimmerOpacity,
            },
          ]}
        />
        <Animated.View
          style={[
            styles.subtitleBox,
            {
              backgroundColor: uiKitTheme.background.tertiary,
              opacity: shimmerOpacity,
            },
          ]}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderRadius: 12,
    overflow: 'hidden',
  },
  imageBox: {
    width: '100%',
    aspectRatio: 16 / 9,
  },
  content: {
    padding: 12,
    gap: 8,
  },
  titleBox: {
    height: 18,
    borderRadius: 4,
    width: '70%',
  },
  subtitleBox: {
    height: 14,
    borderRadius: 4,
    width: '40%',
  },
});
