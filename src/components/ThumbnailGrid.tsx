import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { ActivityIndicator, Image, type LayoutChangeEvent, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { resolveAttachmentUri, resolveAttachmentState, useMediaStore } from '../offline/media';
import type { AttachmentRef } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { CARD_PADDING } from '../ui/tokens';
import { AnchoredMenu } from './AnchoredMenu';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';

export type ThumbnailGridProps = {
  images: AttachmentRef[];
  maxImages?: number;
  size?: 'sm' | 'md' | 'lg';
  tileScale?: number;
  onImagePress?: (image: AttachmentRef, index: number) => void;
  onSetPrimary?: (image: AttachmentRef) => void;
  onDelete?: (image: AttachmentRef) => void;
  onPin?: (image: AttachmentRef) => void;
  onAddImage?: () => void;
  style?: ViewStyle;
};

const TILE_SIZES = {
  sm: { mobile: 80, tablet: 64 },
  md: { mobile: 96, tablet: 80 },
  lg: { mobile: 112, tablet: 96 },
};

export function ThumbnailGrid({
  images,
  maxImages = 5,
  size = 'md',
  tileScale = 1,
  onImagePress,
  onSetPrimary,
  onDelete,
  onPin,
  onAddImage,
  style,
}: ThumbnailGridProps) {
  const uiKitTheme = useUIKitTheme();
  // Subscribe to media store so tiles re-render when upload status changes
  const mediaRecords = useMediaStore((s) => s.records);
  const [menuVisible, setMenuVisible] = useState(false);
  const [menuImage, setMenuImage] = useState<AttachmentRef | null>(null);
  const [menuIndex, setMenuIndex] = useState<number>(-1);
  const [containerWidth, setContainerWidth] = useState(0);

  const GAP = 12;
  const minTileSize = Math.round(TILE_SIZES[size].mobile * tileScale);
  // Calculate tile size to fill the container width evenly
  const tileSize = useMemo(() => {
    if (containerWidth <= 0) return minTileSize;
    // How many tiles fit at minimum size?
    const cols = Math.max(1, Math.floor((containerWidth + GAP) / (minTileSize + GAP)));
    // Expand tiles to fill the row
    return Math.floor((containerWidth - (cols - 1) * GAP) / cols);
  }, [containerWidth, minTileSize]);

  const handleLayout = useCallback((e: LayoutChangeEvent) => {
    setContainerWidth(e.nativeEvent.layout.width);
  }, []);

  const canAddMore = images.length < maxImages;

  const themed = useMemo(
    () =>
      StyleSheet.create({
        tile: {
          borderColor: uiKitTheme.border.primary,
        },
        primaryTile: {
          borderColor: uiKitTheme.primary.main,
          borderWidth: 2,
        },
        primaryBadge: {
          backgroundColor: `${uiKitTheme.primary.main}66`,
        },
        optionsButton: {
          backgroundColor: `${uiKitTheme.primary.main}66`,
        },
        addTile: {
          borderColor: uiKitTheme.border.secondary,
          borderStyle: 'dashed',
        },
      }),
    [uiKitTheme]
  );

  const handleImagePress = useCallback(
    (image: AttachmentRef, index: number) => {
      onImagePress?.(image, index);
    },
    [onImagePress]
  );

  const handleOptionsPress = useCallback(
    (image: AttachmentRef, index: number, e: any) => {
      e.stopPropagation();
      setMenuImage(image);
      setMenuIndex(index);
      setMenuVisible(true);
    },
    []
  );

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
    setMenuImage(null);
    setMenuIndex(-1);
  }, []);

  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    if (!menuImage) return [];
    const items: AnchoredMenuItem[] = [
      {
        label: 'Open',
        onPress: () => {
          if (menuImage && menuIndex >= 0) {
            handleImagePress(menuImage, menuIndex);
          }
          closeMenu();
        },
        icon: 'open-in-new',
      },
    ];

    if (onSetPrimary && !menuImage.isPrimary) {
      items.push({
        label: 'Set Primary',
        onPress: () => {
          if (menuImage) {
            onSetPrimary(menuImage);
          }
          closeMenu();
        },
        icon: 'star',
      });
    }

    if (onPin) {
      items.push({
        label: 'Pin',
        onPress: () => {
          if (menuImage) {
            onPin(menuImage);
          }
          closeMenu();
        },
        icon: 'push-pin',
      });
    }

    if (onDelete) {
      items.push({
        label: 'Delete',
        onPress: () => {
          if (menuImage) {
            onDelete(menuImage);
          }
          closeMenu();
        },
        icon: 'delete',
      });
    }

    return items;
  }, [menuImage, menuIndex, onSetPrimary, onDelete, onPin, handleImagePress, closeMenu]);

  return (
    <>
      <View style={[styles.grid, style]} onLayout={handleLayout}>
        {images.map((image, index) => {
          const resolvedUri = resolveAttachmentUri(image);
          const isPrimary = image.isPrimary ?? false;
          const hasResolvedUri = resolvedUri !== null;
          const attachmentState = resolveAttachmentState(image);
          const isUploading = attachmentState.status === 'uploading';
          const isFailed = attachmentState.status === 'failed';

          return (
            <Pressable
              key={image.url}
              onPress={() => handleImagePress(image, index)}
              style={[
                styles.tile,
                themed.tile,
                isPrimary && themed.primaryTile,
                { width: tileSize, height: tileSize },
              ]}
            >
              {hasResolvedUri ? (
                <Image
                  source={{ uri: resolvedUri }}
                  style={StyleSheet.absoluteFillObject}
                  resizeMode="cover"
                  accessibilityIgnoresInvertColors
                />
              ) : (
                <View style={[StyleSheet.absoluteFillObject, styles.placeholder]}>
                  <MaterialIcons
                    name="image-not-supported"
                    size={24}
                    color={uiKitTheme.text.secondary}
                  />
                </View>
              )}

              {isUploading && (
                <View style={styles.uploadOverlay} pointerEvents="none">
                  <ActivityIndicator size="small" color="#FFFFFF" />
                </View>
              )}

              {isFailed && (
                <View style={styles.uploadOverlay} pointerEvents="none">
                  <MaterialIcons name="cloud-off" size={18} color="#FFFFFF" />
                </View>
              )}

              {isPrimary && (
                <View style={[styles.primaryBadge, themed.primaryBadge]}>
                  <MaterialIcons name="star" size={12} color="#FFFFFF" />
                </View>
              )}

              {(onSetPrimary || onDelete || onPin) && (
                <Pressable
                  onPress={(e) => handleOptionsPress(image, index, e)}
                  style={[styles.optionsButton, themed.optionsButton]}
                  hitSlop={4}
                >
                  <MaterialIcons name="more-vert" size={14} color="#FFFFFF" />
                </Pressable>
              )}
            </Pressable>
          );
        })}

        {canAddMore && onAddImage && (
          <Pressable
            onPress={onAddImage}
            style={[
              styles.tile,
              styles.addTile,
              themed.addTile,
              { width: tileSize, height: tileSize },
            ]}
            accessibilityRole="button"
            accessibilityLabel="Add image"
          >
            <MaterialIcons name="add" size={24} color={uiKitTheme.text.secondary} />
          </Pressable>
        )}
      </View>

      {menuImage && (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title="Image Options"
          showLeadingIcons={true}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  tile: {
    borderRadius: 12,
    borderWidth: 1,
    overflow: 'hidden',
    position: 'relative',
  },
  placeholder: {
    backgroundColor: '#F3F4F6',
    alignItems: 'center',
    justifyContent: 'center',
  },
  uploadOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.35)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryBadge: {
    position: 'absolute',
    top: 4,
    left: 4,
    padding: 4,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: '#FFFFFF',
  },
  optionsButton: {
    position: 'absolute',
    top: 4,
    right: 4,
    padding: 6,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#FFFFFF',
  },
  addTile: {
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
  },
});
