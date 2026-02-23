import { View } from 'react-native';
import { AppText } from './AppText';
import { useTheme } from '../theme/ThemeProvider';
import { Card } from './Card';

type NotesSectionProps = {
  notes: string | null | undefined;
};

export function NotesSection({ notes }: NotesSectionProps) {
  const theme = useTheme();
  const trimmedNotes = notes?.trim();

  return (
    <Card>
      {!trimmedNotes ? (
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          No notes.
        </AppText>
      ) : (
        <AppText variant="body">{trimmedNotes}</AppText>
      )}
    </Card>
  );
}
