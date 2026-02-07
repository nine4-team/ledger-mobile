import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import React, { useCallback, useState, useMemo } from 'react';
import { Platform, Pressable, StyleSheet, View } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as DocumentPicker from 'expo-document-picker';

import { AppText } from './AppText';
import { BottomSheetMenuList } from './BottomSheetMenuList';
import type { AnchoredMenuItem } from './AnchoredMenuList';
import { useUIKitTheme } from '../theme/ThemeProvider';
import type { AttachmentKind } from '../offline/media';

export type ImagePickerButtonProps = {
  onFilePicked: (uri: string, kind: AttachmentKind) => void;
  allowedKinds?: AttachmentKind[];
  maxFiles?: number;
  currentFileCount?: number;
  label?: string;
  style?: any;
};

export function ImagePickerButton({
  onFilePicked,
  allowedKinds = ['image'],
  maxFiles = 50,
  currentFileCount = 0,
  label = 'Add image',
  style,
}: ImagePickerButtonProps) {
  const uiKitTheme = useUIKitTheme();
  const [menuVisible, setMenuVisible] = useState(false);
  const canAddMore = currentFileCount < maxFiles;

  const handlePickFromLibrary = useCallback(async () => {
    setMenuVisible(false);
    const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!permission.granted) {
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.9,
      allowsMultipleSelection: false,
    });
    if (result.canceled || !result.assets[0]) {
      return;
    }
    onFilePicked(result.assets[0].uri, 'image');
  }, [onFilePicked]);

  const handleTakePhoto = useCallback(async () => {
    setMenuVisible(false);
    const permission = await ImagePicker.requestCameraPermissionsAsync();
    if (!permission.granted) {
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.9,
    });
    if (result.canceled || !result.assets[0]) {
      return;
    }
    onFilePicked(result.assets[0].uri, 'image');
  }, [onFilePicked]);

  const handlePickDocument = useCallback(async () => {
    setMenuVisible(false);
    const result = await DocumentPicker.getDocumentAsync({
      type: 'application/pdf',
      copyToCacheDirectory: true,
    });
    if (!result.canceled && result.assets && result.assets[0]) {
      onFilePicked(result.assets[0].uri, 'pdf');
    }
  }, [onFilePicked]);

  const menuItems: AnchoredMenuItem[] = useMemo(() => {
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

  if (!canAddMore) {
    return null;
  }

  // Desktop: Show drag-and-drop zone (simplified for now, can be enhanced)
  if (Platform.OS === 'web') {
    return (
      <Pressable
        onPress={() => setMenuVisible(true)}
        style={[
          styles.addButton,
          {
            borderColor: uiKitTheme.border.secondary,
            backgroundColor: uiKitTheme.background.surface,
          },
          style,
        ]}
        accessibilityRole="button"
        accessibilityLabel={label}
      >
        <MaterialIcons name="add-photo-alternate" size={32} color={uiKitTheme.text.secondary} />
        <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
          Tap to {label.toLowerCase()}
        </AppText>
        <AppText variant="caption" style={{ color: uiKitTheme.text.tertiary, fontSize: 11 }}>
          {currentFileCount} / {maxFiles}
        </AppText>
        <BottomSheetMenuList
          visible={menuVisible}
          onRequestClose={() => setMenuVisible(false)}
          items={menuItems}
          title={label}
          showLeadingIcons={true}
        />
      </Pressable>
    );
  }

  // Mobile: Show action sheet button
  return (
    <>
      <Pressable
        onPress={() => setMenuVisible(true)}
        style={[
          styles.addButton,
          {
            borderColor: uiKitTheme.border.secondary,
            backgroundColor: uiKitTheme.background.surface,
          },
          style,
        ]}
        accessibilityRole="button"
        accessibilityLabel={label}
      >
        <MaterialIcons name="add-photo-alternate" size={32} color={uiKitTheme.text.secondary} />
        <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
          {label}
        </AppText>
        <AppText variant="caption" style={{ color: uiKitTheme.text.tertiary, fontSize: 11 }}>
          {currentFileCount} / {maxFiles}
        </AppText>
      </Pressable>

      <BottomSheetMenuList
        visible={menuVisible}
        onRequestClose={() => setMenuVisible(false)}
        items={menuItems}
        title={label}
        showLeadingIcons={true}
      />
    </>
  );
}

const styles = StyleSheet.create({
  addButton: {
    minHeight: 120,
    borderRadius: 12,
    borderWidth: 2,
    borderStyle: 'dashed',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingVertical: 16,
    paddingHorizontal: 12,
  },
});
