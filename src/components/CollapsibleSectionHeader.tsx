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
};

export function CollapsibleSectionHeader({
  title,
  collapsed,
  onToggle,
  badge,
  style,
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
    paddingHorizontal: 16,
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
  badge: {
    marginLeft: 'auto',
  },
});
