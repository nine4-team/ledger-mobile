import React, { useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppButton } from '../AppButton';
import { AppText } from '../AppText';
import { BottomSheet } from '../BottomSheet';
import { ProjectSelector } from '../ProjectSelector';
import { useTheme } from '../../theme/ThemeProvider';

export interface ReassignToProjectModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  /** Current project to exclude from selector */
  excludeProjectId?: string;
  /** Called with target projectId. Caller does the reassign operation(s). */
  onConfirm: (targetProjectId: string) => void;
  /** Description text. Defaults to single-item copy. */
  description?: string;
  /** For bulk: show eligible/blocked counts */
  bulkInfo?: {
    eligibleCount: number;
    blockedCount: number;
  };
}

export function ReassignToProjectModal({
  visible,
  onRequestClose,
  accountId,
  excludeProjectId,
  onConfirm,
  description,
  bulkInfo,
}: ReassignToProjectModalProps) {
  const theme = useTheme();
  const [targetProjectId, setTargetProjectId] = useState<string | null>(null);

  const handleClose = () => {
    setTargetProjectId(null);
    onRequestClose();
  };

  const handleConfirm = () => {
    if (!targetProjectId) return;
    onConfirm(targetProjectId);
    setTargetProjectId(null);
  };

  const defaultDescription = bulkInfo
    ? `${bulkInfo.eligibleCount} item${bulkInfo.eligibleCount === 1 ? '' : 's'} will be moved directly.\nNo sale or purchase records will be created.`
    : 'Move this item directly to another project. No sale or purchase records will be created.';

  const isDisabled = bulkInfo
    ? bulkInfo.eligibleCount === 0 || !targetProjectId
    : !targetProjectId;

  return (
    <BottomSheet visible={visible} onRequestClose={handleClose}>
      <View style={styles.titleRow}>
        <AppText variant="body" style={styles.title}>Reassign to Project</AppText>
      </View>
      <View style={styles.content}>
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          {description ?? defaultDescription}
        </AppText>
        {bulkInfo && bulkInfo.blockedCount > 0 && (
          <AppText variant="caption" style={{ color: theme.colors.error ?? 'red' }}>
            {bulkInfo.blockedCount} item{bulkInfo.blockedCount === 1 ? ' is' : 's are'} linked to transactions and cannot be reassigned.
          </AppText>
        )}
        <View style={styles.fieldGroup}>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary, fontWeight: '600' }}>
            Target project
          </AppText>
          <ProjectSelector
            accountId={accountId}
            value={targetProjectId}
            onChange={setTargetProjectId}
            excludeProjectId={excludeProjectId}
          />
        </View>
        <AppButton
          title="Reassign"
          variant="primary"
          disabled={isDisabled}
          onPress={handleConfirm}
          style={styles.button}
        />
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  titleRow: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 12,
  },
  title: {
    fontWeight: '700',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 16,
    gap: 12,
  },
  fieldGroup: {
    gap: 8,
  },
  button: {
    minHeight: 44,
  },
});
