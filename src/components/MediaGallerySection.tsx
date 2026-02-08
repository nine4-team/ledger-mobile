import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useMemo, useState } from 'react';
import { Linking, Pressable, StyleSheet, View } from 'react-native';
import type { ViewStyle } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as DocumentPicker from 'expo-document-picker';

import { resolveAttachmentUri } from '../offline/media';
import type { AttachmentRef, AttachmentKind } from '../offline/media';
import { useUIKitTheme } from '../theme/ThemeProvider';
import { AppText } from './AppText';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { ImageGallery } from './ImageGallery';
import { ThumbnailGrid } from './ThumbnailGrid';
import { TitledCard } from './TitledCard';

export type MediaGallerySectionProps = {
  // Content
  title: string;
  attachments: AttachmentRef[];
  maxAttachments?: number;

  // File type support
  allowedKinds?: AttachmentKind[];

  // Handlers (all use AttachmentRef, not just URL strings)
  onAddAttachment?: (localUri: string, kind: AttachmentKind) => void | Promise<void>;
  onRemoveAttachment?: (attachment: AttachmentRef) => void | Promise<void>;
  onSetPrimary?: (attachment: AttachmentRef) => void | Promise<void>;

  // Display customization
  size?: 'sm' | 'md' | 'lg';
  tileScale?: number;
  emptyStateMessage?: string;
  pickerLabel?: string;

  // Style overrides
  style?: ViewStyle;
};

const TILE_SIZES = {
  sm: { mobile: 80, tablet: 64 },
  md: { mobile: 96, tablet: 80 },
  lg: { mobile: 112, tablet: 96 },
};

export function MediaGallerySection({
  title,
  attachments,
  maxAttachments = 5,
  allowedKinds = ['image'],
  onAddAttachment,
  onRemoveAttachment,
  onSetPrimary,
  size = 'md',
  tileScale = 1.5,
  emptyStateMessage,
  pickerLabel,
  style,
}: MediaGallerySectionProps) {
  const uiKitTheme = useUIKitTheme();
  const [galleryVisible, setGalleryVisible] = useState(false);
  const [galleryIndex, setGalleryIndex] = useState(0);
  const [pdfMenuVisible, setPdfMenuVisible] = useState(false);
  const [selectedPdf, setSelectedPdf] = useState<AttachmentRef | null>(null);
  const [addMenuVisible, setAddMenuVisible] = useState(false);

  const tileSize = Math.round(TILE_SIZES[size].mobile * tileScale);

  // Separate images from PDFs
  const imageAttachments = useMemo(
    () => attachments.filter((a) => a.kind === 'image'),
    [attachments]
  );
  const pdfAttachments = useMemo(
    () => attachments.filter((a) => a.kind === 'pdf'),
    [attachments]
  );

  const themed = useMemo(
    () =>
      StyleSheet.create({
        addIconButton: {
          borderColor: uiKitTheme.primary.main,
        },
        fileTile: {
          borderColor: uiKitTheme.border.primary,
          backgroundColor: uiKitTheme.background.tertiary,
        },
        primaryBadge: {
          backgroundColor: `${uiKitTheme.primary.main}66`,
        },
        optionsButton: {
          backgroundColor: `${uiKitTheme.primary.main}66`,
        },
      }),
    [uiKitTheme]
  );

  const handleImagePress = useCallback((image: AttachmentRef, index: number) => {
    setGalleryIndex(index);
    setGalleryVisible(true);
  }, []);

  const handlePdfPress = useCallback(async (pdf: AttachmentRef) => {
    const resolvedUri = resolveAttachmentUri(pdf);
    if (resolvedUri) {
      try {
        await Linking.openURL(resolvedUri);
      } catch (error) {
        console.error('Failed to open PDF:', error);
      }
    }
  }, []);

  const handlePdfOptionsPress = useCallback((pdf: AttachmentRef, e: any) => {
    e.stopPropagation();
    setSelectedPdf(pdf);
    setPdfMenuVisible(true);
  }, []);

  const closePdfMenu = useCallback(() => {
    setPdfMenuVisible(false);
    setSelectedPdf(null);
  }, []);

  const handlePickFromLibrary = useCallback(async () => {
    setAddMenuVisible(false);
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) return;

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.9,
      allowsMultipleSelection: false,
    });

    if (!result.canceled && result.assets[0] && onAddAttachment) {
      await onAddAttachment(result.assets[0].uri, 'image');
    }
  }, [onAddAttachment]);

  const handleTakePhoto = useCallback(async () => {
    setAddMenuVisible(false);
    const permission = await ImagePicker.requestCameraPermissionsAsync();
    if (!permission.granted) return;

    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.9,
    });

    if (!result.canceled && result.assets[0] && onAddAttachment) {
      await onAddAttachment(result.assets[0].uri, 'image');
    }
  }, [onAddAttachment]);

  const handlePickDocument = useCallback(async () => {
    setAddMenuVisible(false);
    const result = await DocumentPicker.getDocumentAsync({
      type: 'application/pdf',
      copyToCacheDirectory: true,
    });

    if (!result.canceled && result.assets?.[0] && onAddAttachment) {
      await onAddAttachment(result.assets[0].uri, 'pdf');
    }
  }, [onAddAttachment]);

  const addMenuItems = useMemo<AnchoredMenuItem[]>(() => {
    const items: AnchoredMenuItem[] = [
      {
        label: 'Camera',
        onPress: handleTakePhoto,
        icon: 'camera-alt',
      },
      {
        label: 'Photo Library',
        onPress: handlePickFromLibrary,
        icon: 'photo-library',
      },
    ];

    if (allowedKinds.includes('pdf')) {
      items.push({
        label: 'Files',
        onPress: handlePickDocument,
        icon: 'insert-drive-file',
      });
    }

    return items;
  }, [allowedKinds, handleTakePhoto, handlePickFromLibrary, handlePickDocument]);

  const pdfMenuItems = useMemo<AnchoredMenuItem[]>(() => {
    if (!selectedPdf) return [];
    const items: AnchoredMenuItem[] = [
      {
        label: 'Open file',
        onPress: () => {
          if (selectedPdf) {
            handlePdfPress(selectedPdf);
          }
          closePdfMenu();
        },
        icon: 'open-in-new',
      },
    ];

    if (onSetPrimary) {
      items.push({
        label: 'Set primary',
        onPress: () => {
          if (selectedPdf && onSetPrimary) {
            onSetPrimary(selectedPdf);
          }
          closePdfMenu();
        },
        icon: 'star',
      });
    }

    if (onRemoveAttachment) {
      items.push({
        label: 'Delete',
        onPress: () => {
          if (selectedPdf && onRemoveAttachment) {
            onRemoveAttachment(selectedPdf);
          }
          closePdfMenu();
        },
        icon: 'delete',
      });
    }

    return items;
  }, [selectedPdf, onSetPrimary, onRemoveAttachment, handlePdfPress, closePdfMenu]);

  const defaultEmptyMessage = emptyStateMessage ??
    (allowedKinds.includes('pdf') ? 'No receipts yet.' : 'No images yet.');

  const defaultPickerLabel = pickerLabel ??
    (allowedKinds.includes('pdf') ? 'Add receipt' : 'Add image');

  const showEmptyState = attachments.length === 0;
  const canAddMore = attachments.length < maxAttachments;

  return (
    <>
      <TitledCard title={title} containerStyle={style} cardStyle={styles.cardWithButton}>
        {/* Add button in top-right corner */}
        {canAddMore && onAddAttachment && (
          <Pressable
            onPress={() => setAddMenuVisible(true)}
            style={[
              styles.addIconButton,
              themed.addIconButton,
              { backgroundColor: uiKitTheme.background.surface },
            ]}
            hitSlop={8}
          >
            <MaterialIcons name="add" size={20} color={uiKitTheme.text.primary} />
          </Pressable>
        )}

        {showEmptyState ? (
          <View style={styles.emptyState}>
            <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
              {defaultEmptyMessage}
            </AppText>
          </View>
        ) : (
          <View style={styles.content}>
            {/* Image thumbnails */}
            {imageAttachments.length > 0 && (
              <ThumbnailGrid
                images={imageAttachments}
                maxImages={maxAttachments}
                size={size}
                tileScale={tileScale}
                onImagePress={handleImagePress}
                onSetPrimary={onSetPrimary}
                onDelete={onRemoveAttachment}
              />
            )}

            {/* PDF file tiles */}
            {pdfAttachments.length > 0 && (
              <View style={[styles.fileGrid, imageAttachments.length > 0 && styles.fileGridMargin]}>
                {pdfAttachments.map((pdf) => (
                  <Pressable
                    key={pdf.url}
                    onPress={() => handlePdfPress(pdf)}
                    style={[styles.fileTile, themed.fileTile, { width: tileSize, height: tileSize }]}
                  >
                    <View style={styles.fileContent}>
                      <MaterialIcons
                        name="picture-as-pdf"
                        size={32}
                        color={uiKitTheme.text.secondary}
                      />
                      <AppText variant="caption" style={styles.fileLabel} numberOfLines={1}>
                        {pdf.fileName || 'PDF'}
                      </AppText>
                    </View>

                    {/* Primary badge if applicable */}
                    {pdf.isPrimary && (
                      <View style={[styles.primaryBadge, themed.primaryBadge]}>
                        <MaterialIcons name="star" size={12} color="#FFFFFF" />
                      </View>
                    )}

                    {/* Options menu */}
                    {(onSetPrimary || onRemoveAttachment) && (
                      <Pressable
                        onPress={(e) => handlePdfOptionsPress(pdf, e)}
                        style={[styles.optionsButton, themed.optionsButton]}
                        hitSlop={4}
                      >
                        <MaterialIcons name="more-vert" size={14} color="#FFFFFF" />
                      </Pressable>
                    )}
                  </Pressable>
                ))}
              </View>
            )}
          </View>
        )}
      </TitledCard>

      {/* Add menu */}
      <BottomSheetMenuList
        visible={addMenuVisible}
        onRequestClose={() => setAddMenuVisible(false)}
        items={addMenuItems}
        title={defaultPickerLabel}
        showLeadingIcons={true}
      />

      {/* Image gallery modal (images only) */}
      {imageAttachments.length > 0 && (
        <ImageGallery
          images={imageAttachments}
          visible={galleryVisible}
          initialIndex={galleryIndex}
          onRequestClose={() => setGalleryVisible(false)}
        />
      )}

      {/* PDF menu */}
      {selectedPdf && (
        <BottomSheetMenuList
          visible={pdfMenuVisible}
          onRequestClose={closePdfMenu}
          items={pdfMenuItems}
          title="Attachment options"
          showLeadingIcons={true}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  cardWithButton: {
    position: 'relative',
  },
  addIconButton: {
    position: 'absolute',
    top: 8,
    right: 8,
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    zIndex: 10,
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 16,
  },
  content: {
    gap: 12,
  },
  fileGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  fileGridMargin: {
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
});
