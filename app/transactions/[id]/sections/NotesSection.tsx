import { useState } from 'react';
import { Pressable, View, StyleSheet } from 'react-native';
import { Card } from '../../../../src/components/Card';
import { AppText } from '../../../../src/components/AppText';
import { useTheme } from '../../../../src/theme/ThemeProvider';
import type { Transaction } from '../../../../src/data/transactionsService';

type NotesSectionProps = {
  transaction: Transaction;
};

export function NotesSection({ transaction }: NotesSectionProps) {
  const theme = useTheme();
  const [isExpanded, setIsExpanded] = useState(false);

  const trimmedNotes = transaction.notes?.trim();
  const shouldShowToggle = trimmedNotes && trimmedNotes.length > 120;

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
