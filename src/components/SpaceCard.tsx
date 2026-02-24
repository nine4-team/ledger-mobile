import React, { useMemo } from 'react';
import type { ViewStyle } from 'react-native';
import { TouchableOpacity, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { AppText } from './AppText';
import { ImageCard } from './ImageCard';
import { ProgressBar } from './ProgressBar';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { resolveAttachmentUri } from '../offline/media';
import type { AttachmentRef } from '../offline/media';
import type { Checklist } from '../data/spacesService';

export type SpaceCardProps = {
  name: string;
  itemCount: number;
  primaryImage?: AttachmentRef | null;
  checklists?: Checklist[] | null;
  notes?: string | null;
  showNotes?: boolean;
  onPress: () => void;
  onMenuPress?: () => void;
  style?: ViewStyle;
};

export function SpaceCard({
  name,
  itemCount,
  primaryImage,
  checklists,
  notes,
  showNotes = true,
  onPress,
  onMenuPress,
  style,
}: SpaceCardProps) {
  const uiKitTheme = useUIKitTheme();
  const theme = useTheme();

  const imageUri = useMemo(() => {
    if (!primaryImage) return null;
    const resolved = resolveAttachmentUri(primaryImage);
    return resolved ?? (primaryImage.url.startsWith('offline://') ? null : primaryImage.url);
  }, [primaryImage]);

  const checklistProgress = useMemo(() => {
    if (!checklists || checklists.length === 0) return null;
    let total = 0;
    let checked = 0;
    for (const cl of checklists) {
      for (const item of cl.items) {
        total++;
        if (item.isChecked) checked++;
      }
    }
    if (total === 0) return null;
    return { checked, total, percentage: (checked / total) * 100 };
  }, [checklists]);

  return (
    <ImageCard
      imageUri={imageUri}
      onPress={onPress}
      style={style}
      accessibilityLabel={`${name}, ${itemCount} items${
        checklistProgress
          ? `, ${checklistProgress.checked} of ${checklistProgress.total} checklist items completed`
          : ''
      }`}
      accessibilityHint="Tap to view space details"
    >
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' }}>
        <View style={{ flex: 1, gap: 3 }}>
          <AppText
            variant="body"
            style={{ fontWeight: '600' }}
            numberOfLines={2}
            ellipsizeMode="tail"
          >
            {name?.trim() || 'Untitled space'}
          </AppText>
          <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
            {itemCount} {itemCount === 1 ? 'item' : 'items'}
          </AppText>
          {checklistProgress && (
            <View style={{ gap: 3, marginTop: 2 }}>
              <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
                {checklistProgress.checked}/{checklistProgress.total} completed
              </AppText>
              <ProgressBar
                percentage={checklistProgress.percentage}
                color="#22C55E"
                height={6}
              />
            </View>
          )}
          {showNotes && notes && (
            <AppText
              variant="caption"
              style={{ color: uiKitTheme.text.secondary, marginTop: 6 }}
              numberOfLines={2}
              ellipsizeMode="tail"
            >
              {notes}
            </AppText>
          )}
        </View>
        {onMenuPress && (
          <TouchableOpacity
            onPress={onMenuPress}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            accessibilityLabel="Space options"
            accessibilityRole="button"
            style={{ marginLeft: 8, marginTop: -2 }}
          >
            <MaterialIcons name="more-vert" size={24} color={theme.colors.primary} />
          </TouchableOpacity>
        )}
      </View>
    </ImageCard>
  );
}
