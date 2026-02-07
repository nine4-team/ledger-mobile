import React, { useCallback, useMemo, useState } from 'react';
import { Image, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';

export type ImageCardProps = {
  imageUri?: string | null;
  onPress: () => void;
  children: React.ReactNode;
  /** Show placeholder when no image (default true) */
  showPlaceholder?: boolean;
  /** Image aspect ratio (default 16/9) */
  imageAspectRatio?: number;
  style?: ViewStyle;
  accessibilityLabel?: string;
  accessibilityHint?: string;
};

export function ImageCard({
  imageUri,
  onPress,
  children,
  showPlaceholder = true,
  imageAspectRatio = 5 / 2,
  style,
  accessibilityLabel,
  accessibilityHint,
}: ImageCardProps) {
  const uiKitTheme = useUIKitTheme();
  const [imageLoading, setImageLoading] = useState(true);
  const [imageError, setImageError] = useState(false);

  const handleImageLoad = useCallback(() => {
    setImageLoading(false);
  }, []);

  const handleImageError = useCallback(() => {
    setImageLoading(false);
    setImageError(true);
  }, []);

  const hasImage = imageUri != null && !imageError;
  const showImageArea = hasImage || showPlaceholder;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        card: {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.surface,
        },
        placeholder: {
          backgroundColor: uiKitTheme.background.tertiary,
        },
        loading: {
          backgroundColor: uiKitTheme.background.tertiary,
        },
      }),
    [uiKitTheme]
  );

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        themed.card,
        { opacity: pressed ? 0.8 : 1 },
        style,
      ]}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityHint={accessibilityHint}
    >
      {showImageArea && (
        <View style={[styles.imageContainer, { aspectRatio: imageAspectRatio }]}>
          {hasImage && imageUri ? (
            <>
              {imageLoading && (
                <View style={[StyleSheet.absoluteFill, themed.loading]} />
              )}
              <Image
                source={{ uri: imageUri }}
                style={styles.image}
                resizeMode="cover"
                onLoad={handleImageLoad}
                onError={handleImageError}
                accessibilityIgnoresInvertColors
              />
            </>
          ) : (
            <View style={[styles.placeholder, themed.placeholder]}>
              <AppText variant="caption" style={{ color: uiKitTheme.text.tertiary }}>
                No image
              </AppText>
            </View>
          )}
        </View>
      )}
      <View style={styles.content}>
        {children}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderWidth: 1,
    borderRadius: 12,
    overflow: 'hidden',
  },
  imageContainer: {
    width: '100%',
    position: 'relative',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  placeholder: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    padding: 12,
    gap: 4,
  },
});
