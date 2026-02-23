import React, { useEffect, useRef } from 'react';
import { Animated, StyleSheet } from 'react-native';

import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { useToastStore } from './toastStore';

export function Toast() {
  const message = useToastStore((s) => s.message);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const opacity = useRef(new Animated.Value(0)).current;
  const translateY = useRef(new Animated.Value(10)).current;

  useEffect(() => {
    if (message) {
      Animated.parallel([
        Animated.timing(opacity, {
          toValue: 1,
          duration: 200,
          useNativeDriver: true,
        }),
        Animated.timing(translateY, {
          toValue: 0,
          duration: 200,
          useNativeDriver: true,
        }),
      ]).start();
    } else {
      Animated.parallel([
        Animated.timing(opacity, {
          toValue: 0,
          duration: 150,
          useNativeDriver: true,
        }),
        Animated.timing(translateY, {
          toValue: 10,
          duration: 150,
          useNativeDriver: true,
        }),
      ]).start();
    }
  }, [message, opacity, translateY]);

  if (!message) return null;

  return (
    <Animated.View
      pointerEvents="none"
      style={[
        styles.container,
        {
          opacity,
          transform: [{ translateY }],
          backgroundColor: uiKitTheme.background.surface,
          borderColor: uiKitTheme.border.secondary,
        },
      ]}
    >
      <AppText variant="caption" style={[styles.text, { color: theme.colors.text }]}>
        {message}
      </AppText>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 100,
    alignSelf: 'center',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 22,
    borderWidth: 1,
    zIndex: 9999,
    elevation: 10,
  },
  text: {
    fontWeight: '600',
    textAlign: 'center',
  },
});
