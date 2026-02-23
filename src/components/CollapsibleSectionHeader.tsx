import { Pressable, View, StyleSheet, type ViewStyle } from 'react-native';
import { MaterialIcons } from '@expo/vector-icons';
import { AppText } from './AppText';
import { useUIKitTheme } from '../theme/ThemeProvider';

export type CollapsibleSectionHeaderProps = {
  title: string;
  collapsed: boolean;
  onToggle: () => void;
  badge?: string;
  style?: ViewStyle;
  /** When provided, renders a pencil edit icon that triggers this callback. */
  onEdit?: () => void;
  /** When provided, renders a plus icon that triggers this callback. */
  onAdd?: () => void;
};

export function CollapsibleSectionHeader({
  title,
  collapsed,
  onToggle,
  badge,
  style,
  onEdit,
  onAdd,
}: CollapsibleSectionHeaderProps) {
  const uiKitTheme = useUIKitTheme();

  return (
    <Pressable
      onPress={onToggle}
      style={[styles.container, style]}
      accessibilityRole="button"
      accessibilityLabel={`${title} section, ${collapsed ? 'collapsed' : 'expanded'}`}
    >
      <View style={styles.content}>
        <MaterialIcons
          name={collapsed ? 'chevron-right' : 'expand-more'}
          size={24}
          color={uiKitTheme.text.secondary}
        />
        <AppText variant="caption" style={[styles.title, { color: uiKitTheme.text.secondary }]}>
          {title}
        </AppText>
        {onEdit && (
          <Pressable
            onPress={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={`Edit ${title} section`}
            style={styles.editButton}
          >
            <MaterialIcons
              name="edit"
              size={16}
              color={uiKitTheme.primary.main}
            />
          </Pressable>
        )}
        {onAdd && (
          <Pressable
            onPress={(e) => {
              e.stopPropagation();
              onAdd();
            }}
            hitSlop={8}
            accessibilityRole="button"
            accessibilityLabel={`Add to ${title} section`}
          >
            <MaterialIcons
              name="add-circle-outline"
              size={20}
              color={uiKitTheme.primary.main}
            />
          </Pressable>
        )}
        {badge && (
          <AppText variant="caption" style={[styles.badge, { color: uiKitTheme.text.tertiary }]}>
            {badge}
          </AppText>
        )}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 0,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  title: {
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    fontWeight: '600',
  },
  editButton: {
    marginLeft: 4,
    padding: 4,
  },
  badge: {
    marginLeft: 'auto',
  },
});
