import React from 'react';
import { StyleSheet, View } from 'react-native';

import { AppText } from '../AppText';
import { BottomSheet } from '../BottomSheet';
import { SpacePickerList } from './SpacePickerList';
import { useTheme } from '../../theme/ThemeProvider';

export interface SetSpaceModalProps {
  visible: boolean;
  onRequestClose: () => void;
  projectId: string | null;
  /** Current spaceId for single-item context (shows as pre-selected). Pass null for bulk. */
  currentSpaceId?: string | null;
  /** Called with selected spaceId. Caller does the updateItem(s). */
  onConfirm: (spaceId: string | null) => void;
  /** Optional subtitle like "3 items selected" */
  subtitle?: string;
  /** Title override — default "Set Space" */
  title?: string;
}

export function SetSpaceModal({
  visible,
  onRequestClose,
  projectId,
  currentSpaceId = null,
  onConfirm,
  subtitle,
  title = 'Set Space',
}: SetSpaceModalProps) {
  const theme = useTheme();

  const handleChange = (spaceId: string | null) => {
    onConfirm(spaceId);
    onRequestClose();
  };

  return (
    <BottomSheet visible={visible} onRequestClose={onRequestClose}>
      <View style={styles.content}>
        <AppText variant="body" style={styles.title}>{title}</AppText>
        {subtitle ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {subtitle}
          </AppText>
        ) : null}
        <SpacePickerList
          projectId={projectId}
          selectedId={currentSpaceId}
          onSelect={handleChange}
          allowCreate
          maxHeight={250}
        />
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingHorizontal: 16,
    paddingBottom: 16,
    paddingTop: 8,
    gap: 12,
  },
  title: {
    fontWeight: '700',
  },
});
