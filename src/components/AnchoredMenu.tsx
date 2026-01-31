import React from 'react';
import { Modal, Pressable, StyleSheet, View, ViewStyle, useWindowDimensions } from 'react-native';

import { useUIKitTheme } from '../theme/ThemeProvider';
import { SCREEN_PADDING } from '../ui';

export type AnchorLayout = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export interface AnchoredMenuProps {
  visible: boolean;
  anchorLayout: AnchorLayout | null;
  onRequestClose: () => void;
  width?: number;
  maxWidth?: number;
  offsetY?: number;
  containerStyle?: ViewStyle;
  children: React.ReactNode;
}

export function AnchoredMenu({
  visible,
  anchorLayout,
  onRequestClose,
  width = 220,
  maxWidth = 280,
  offsetY = 4,
  containerStyle,
  children,
}: AnchoredMenuProps) {
  const uiKitTheme = useUIKitTheme();
  const { width: screenWidth } = useWindowDimensions();

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onRequestClose}>
      <Pressable style={styles.overlay} onPress={onRequestClose}>
        {anchorLayout && (() => {
          const buttonRightEdge = anchorLayout.x + anchorLayout.width;
          let left = buttonRightEdge - width;
          left = Math.max(SCREEN_PADDING, Math.min(left, screenWidth - width - SCREEN_PADDING));

          return (
            <View
              style={[
                styles.container,
                {
                  backgroundColor: uiKitTheme.background.modal,
                  borderColor: uiKitTheme.border.secondary,
                  top: anchorLayout.y + anchorLayout.height + offsetY,
                  left,
                  width,
                  maxWidth,
                },
                containerStyle,
              ]}
              onStartShouldSetResponder={() => true}
            >
              {children}
            </View>
          );
        })()}
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.1)',
  },
  container: {
    position: 'absolute',
    borderRadius: 8,
    borderWidth: 1,
    minWidth: 220,
    shadowOpacity: 0.2,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 5,
    overflow: 'hidden',
  },
});
