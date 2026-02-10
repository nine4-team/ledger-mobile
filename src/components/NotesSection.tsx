import { useState } from 'react';
import { Pressable, View, StyleSheet } from 'react-native';
import { AppText } from './AppText';
import { useTheme } from '../theme/ThemeProvider';
import { Card } from './Card';

type NotesSectionProps = {
  notes: string | null | undefined;
  expandable?: boolean;
};

export function NotesSection({ notes, expandable = false }: NotesSectionProps) {
  const theme = useTheme();
  const [isExpanded, setIsExpanded] = useState(false);

  const trimmedNotes = notes?.trim();
  const shouldShowToggle = expandable && trimmedNotes && trimmedNotes.length > 120;

  return (
    <Card>
      {!trimmedNotes ? (
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          No notes.
        </AppText>
      ) : (
        <Pressable
          onPress={() => setIsExpanded((prev) => !prev)}
          disabled={!shouldShowToggle}
        >
          <AppText variant="body" numberOfLines={isExpanded ? undefined : shouldShowToggle ? 2 : undefined}>
            {trimmedNotes}
          </AppText>
          {shouldShowToggle && (
            <AppText variant="caption" style={[styles.toggleText, { color: theme.colors.primary }]}>
              {isExpanded ? 'Show less' : 'Show more'}
            </AppText>
          )}
        </Pressable>
      )}
    </Card>
  );
}

const styles = StyleSheet.create({
  toggleText: {
    marginTop: 4,
  },
});
