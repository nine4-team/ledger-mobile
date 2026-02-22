import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Image, Linking, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';

import { resolveAttachmentUri } from '../offline/media';
import type { AttachmentRef } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { ThumbnailGrid } from './ThumbnailGrid';
import { AppText } from './AppText';

export type TransactionAttachmentPreviewProps = {
  attachments: AttachmentRef[];
  maxAttachments?: number;
  size?: 'sm' | 'md' | 'lg';
  onImagePress?: (image: AttachmentRef, index: number) => void;
  onDelete?: (attachment: AttachmentRef) => void;
  onPin?: (attachment: AttachmentRef) => void;
  onAddAttachment?: () => void;
  style?: ViewStyle;
};

const TILE_SIZES = {
  sm: { mobile: 80, tablet: 64 },
  md: { mobile: 96, tablet: 80 },
  lg: { mobile: 112, tablet: 96 },
};

function isImageAttachment(attachment: AttachmentRef): boolean {
  return attachment.kind === 'image';
}

function isPdfAttachment(attachment: AttachmentRef): boolean {
  return attachment.kind === 'pdf';
}

export function TransactionAttachmentPreview({
  attachments,
  maxAttachments = 10,
  size = 'md',
  onImagePress,
  onDelete,
  onPin,
  onAddAttachment,
  style,
}: TransactionAttachmentPreviewProps) {
  const uiKitTheme = useUIKitTheme();
  const [menuVisible, setMenuVisible] = useState(false);
  const [menuAttachment, setMenuAttachment] = useState<AttachmentRef | null>(null);
  const [menuIndex, setMenuIndex] = useState<number>(-1);

  const tileSize = TILE_SIZES[size].mobile;
  const canAddMore = attachments.length < maxAttachments;

  // Separate images from non-images (PDFs/files)
  const imageAttachments = useMemo(
    () => attachments.filter((a) => isImageAttachment(a)),
    [attachments]
  );
  const nonImageAttachments = useMemo(
    () => attachments.filter((a) => !isImageAttachment(a)),
    [attachments]
  );

  const themed = useMemo(
    () =>
      StyleSheet.create({
        fileTile: {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.tertiary,
        },
        addTile: {
          borderColor: uiKitTheme.border.secondary,
          borderStyle: 'dashed',
        },
      }),
    [uiKitTheme]
  );

  const handleFilePress = useCallback(
    async (attachment: AttachmentRef) => {
      const resolvedUri = resolveAttachmentUri(attachment);
      if (resolvedUri) {
        try {
          await Linking.openURL(resolvedUri);
        } catch (error) {
          console.error('Failed to open file:', error);
        }
      }
    },
    []
  );

  const handleOptionsPress = useCallback(
    (attachment: AttachmentRef, index: number, e: any) => {
      e.stopPropagation();
      setMenuAttachment(attachment);
      setMenuIndex(index);
      setMenuVisible(true);
    },
    []
  );

  const closeMenu = useCallback(() => {
    setMenuVisible(false);
    setMenuAttachment(null);
    setMenuIndex(-1);
  }, []);

  const menuItems = useMemo<AnchoredMenuItem[]>(() => {
    if (!menuAttachment) return [];
    const items: AnchoredMenuItem[] = [];

    if (isImageAttachment(menuAttachment)) {
      items.push({
        label: 'Open',
        onPress: () => {
          if (menuAttachment && onImagePress) {
            const imageIndex = imageAttachments.findIndex((a) => a.url === menuAttachment.url);
            if (imageIndex >= 0) {
              onImagePress(menuAttachment, imageIndex);
            }
          }
          closeMenu();
        },
        icon: 'open-in-new',
      });
    } else {
      items.push({
        label: 'Open File',
        onPress: () => {
          if (menuAttachment) {
            handleFilePress(menuAttachment);
          }
          closeMenu();
        },
        icon: 'open-in-new',
      });
    }

    if (onPin && isImageAttachment(menuAttachment)) {
      items.push({
        label: 'Pin',
        onPress: () => {
          if (menuAttachment) {
            onPin(menuAttachment);
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
          if (menuAttachment) {
            onDelete(menuAttachment);
          }
          closeMenu();
        },
        icon: 'delete',
      });
    }

    return items;
  }, [menuAttachment, menuIndex, onImagePress, onDelete, onPin, handleFilePress, closeMenu, imageAttachments]);

  return (
    <>
      <View style={style}>
        {/* Image attachments grid */}
        {imageAttachments.length > 0 && (
          <ThumbnailGrid
            images={imageAttachments}
            maxImages={maxAttachments}
            size={size}
            onImagePress={onImagePress}
            onDelete={onDelete}
            onPin={onPin}
            onAddImage={canAddMore && imageAttachments.length < maxAttachments ? onAddAttachment : undefined}
          />
        )}

        {/* Non-image attachments (PDFs/files) */}
        {nonImageAttachments.length > 0 && (
          <View style={styles.fileGrid}>
            {nonImageAttachments.map((attachment, index) => {
              const isPdf = isPdfAttachment(attachment);
              return (
                <Pressable
                  key={attachment.url}
                  onPress={() => handleFilePress(attachment)}
                  style={[styles.fileTile, themed.fileTile, { width: tileSize, height: tileSize }]}
                >
                  <View style={styles.fileContent}>
                    <MaterialIcons
                      name={isPdf ? 'picture-as-pdf' : 'description'}
                      size={32}
                      color={uiKitTheme.text.secondary}
                    />
                    <AppText variant="caption" style={styles.fileLabel} numberOfLines={1}>
                      {isPdf ? 'PDF' : attachment.fileName || 'File'}
                    </AppText>
                  </View>

                  {onDelete && (
                    <Pressable
                      onPress={(e) => handleOptionsPress(attachment, index, e)}
                      style={styles.fileOptionsButton}
                      hitSlop={4}
                    >
                      <MaterialIcons name="more-vert" size={14} color={uiKitTheme.text.secondary} />
                    </Pressable>
                  )}
                </Pressable>
              );
            })}
          </View>
        )}

        {/* Add attachment button (if no images shown yet) */}
        {imageAttachments.length === 0 && canAddMore && onAddAttachment && (
          <Pressable
            onPress={onAddAttachment}
            style={[styles.addTile, themed.addTile, { width: tileSize, height: tileSize }]}
            accessibilityRole="button"
            accessibilityLabel="Add attachment"
          >
            <MaterialIcons name="add" size={24} color={uiKitTheme.text.secondary} />
          </Pressable>
        )}
      </View>

      {menuAttachment && (
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={closeMenu}
          items={menuItems}
          title="Attachment Options"
          showLeadingIcons={true}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  fileGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    marginTop: 12,
  },
  fileTile: {
    borderRadius: 12,
    borderWidth: 1,
    overflow: 'hidden',
    position: 'relative',
    alignItems: 'center',
    justifyContent: 'center',
  },
  fileContent: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: 8,
  },
  fileLabel: {
    textAlign: 'center',
  },
  fileOptionsButton: {
    position: 'absolute',
    top: 4,
    right: 4,
    padding: 4,
  },
  addTile: {
    borderWidth: 2,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
  },
});
