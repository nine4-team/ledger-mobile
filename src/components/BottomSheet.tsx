import React, { useEffect, useMemo } from 'react';
import {
  Animated,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  View,
  ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useUIKitTheme } from '../theme/ThemeProvider';

export interface BottomSheetProps {
  visible: boolean;
  onRequestClose: () => void;
  /**
   * Optional style override for the sheet container.
   */
  containerStyle?: ViewStyle;
  children: React.ReactNode;
}

export function BottomSheet({ visible, onRequestClose, containerStyle, children }: BottomSheetProps) {
  const uiKitTheme = useUIKitTheme();
  const insets = useSafeAreaInsets();
  // Note: our lint rules disallow accessing ref `.current` during render.
  // Animated.Value instances are stable when created via `useMemo`.
  const translateY = useMemo(() => new Animated.Value(24), []);
  const overlayOpacity = useMemo(() => new Animated.Value(0), []);

  const sheetPaddingBottom = useMemo(() => Math.max(12, insets.bottom), [insets.bottom]);

  useEffect(() => {
    if (!visible) return;
    translateY.setValue(24);
    overlayOpacity.setValue(0);
    Animated.parallel([
      Animated.timing(overlayOpacity, {
        toValue: 1,
        duration: 160,
        useNativeDriver: true,
      }),
      Animated.timing(translateY, {
        toValue: 0,
        duration: 180,
        useNativeDriver: true,
      }),
    ]).start();
  }, [overlayOpacity, translateY, visible]);

  if (!visible) return null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onRequestClose}
      statusBarTranslucent={Platform.OS === 'android'}
    >
      <View style={styles.root} accessibilityViewIsModal>
        <Animated.View
          pointerEvents="none"
          style={[
            styles.overlay,
            {
              opacity: overlayOpacity,
            },
          ]}
        />
        <Pressable
          style={StyleSheet.absoluteFill}
          accessibilityRole="button"
          accessibilityLabel="Close menu"
          onPress={onRequestClose}
        />
        <Animated.View
          style={[
            styles.sheet,
            {
              backgroundColor: uiKitTheme.background.modal ?? uiKitTheme.background.surface,
              borderColor: uiKitTheme.border.secondary,
              paddingBottom: sheetPaddingBottom,
              transform: [{ translateY }],
            },
            containerStyle,
          ]}
        >
          <View style={[styles.handle, { backgroundColor: uiKitTheme.border.secondary }]} />
          {children}
        </Animated.View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.35)',
  },
  sheet: {
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
    borderWidth: 1,
    overflow: 'hidden',
    paddingTop: 8,
  },
  handle: {
    alignSelf: 'center',
    width: 42,
    height: 4,
    borderRadius: 999,
    opacity: 0.9,
    marginBottom: 8,
  },
});

