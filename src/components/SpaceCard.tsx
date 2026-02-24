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
    const rows = checklists
      .map((cl) => {
        const total = cl.items.length;
        const checked = cl.items.filter((i) => i.isChecked).length;
        return { id: cl.id, name: cl.name, checked, total, percentage: total > 0 ? (checked / total) * 100 : 0 };
      })
      .filter((row) => row.total > 0);
    return rows.length > 0 ? rows : null;
  }, [checklists]);

  const accessibilityDesc = checklistProgress
    ? checklistProgress.map((r) => `${r.name}: ${r.checked} of ${r.total} completed`).join(', ')
    : '';

  return (
    <ImageCard
      imageUri={imageUri}
      onPress={onPress}
      style={style}
      accessibilityLabel={`${name}, ${itemCount} items${accessibilityDesc ? `, ${accessibilityDesc}` : ''}`}
      accessibilityHint="Tap to view space details"
    >
      <View style={{ gap: 3 }}>
        {/* Name row with optional kebab */}
        <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' }}>
          <AppText
            variant="body"
            style={{ fontWeight: '600', flex: 1 }}
            numberOfLines={2}
            ellipsizeMode="tail"
          >
            {name?.trim() || 'Untitled space'}
          </AppText>
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

        {/* Item count */}
        <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
          {itemCount} {itemCount === 1 ? 'item' : 'items'}
        </AppText>

        {/* Per-checklist progress bars — full width */}
        {checklistProgress && (
          <View style={{ gap: 8, marginTop: 6 }}>
            {checklistProgress.map((row) => (
              <View key={row.id} style={{ gap: 3 }}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                  <AppText variant="caption" style={{ color: uiKitTheme.text.secondary, flex: 1 }} numberOfLines={1} ellipsizeMode="tail">
                    {row.name}
                  </AppText>
                  <AppText variant="caption" style={{ color: uiKitTheme.text.secondary, marginLeft: 8, flexShrink: 0 }}>
                    {row.checked}/{row.total}
                  </AppText>
                </View>
                <ProgressBar
                  percentage={row.percentage}
                  color="#22C55E"
                  height={5}
                />
              </View>
            ))}
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
    </ImageCard>
  );
}
