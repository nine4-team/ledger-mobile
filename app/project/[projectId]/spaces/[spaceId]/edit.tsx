import { useEffect, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../../../src/components/Screen';
import { AppText } from '../../../../../src/components/AppText';
import { AppButton } from '../../../../../src/components/AppButton';
import { useAccountContextStore } from '../../../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../../../../src/ui/styles/forms';
import { layout } from '../../../../../src/ui';
import { Space, subscribeToSpace, updateSpace } from '../../../../../src/data/spacesService';

type SpaceParams = {
  projectId?: string;
  spaceId?: string;
};

export default function EditSpaceScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<SpaceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [space, setSpace] = useState<Space | null>(null);
  const [name, setName] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!accountId || !spaceId) {
      setSpace(null);
      return;
    }
    const unsubscribe = subscribeToSpace(accountId, spaceId, (next) => {
      setSpace(next);
      setName(next?.name ?? '');
      setNotes(next?.notes ?? '');
    });
    return () => unsubscribe();
  }, [accountId, spaceId]);

  const handleSubmit = async () => {
    if (!accountId || !spaceId) return;
    if (!name.trim()) {
      setError('Space name is required.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      await updateSpace(accountId, spaceId, {
        name: name.trim(),
        notes: notes.trim() || null,
      });
      if (projectId) {
        router.replace(`/project/${projectId}/spaces/${spaceId}`);
      } else {
        router.back();
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to update space.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const backTarget = projectId && spaceId ? `/project/${projectId}/spaces/${spaceId}` : undefined;

  return (
    <Screen title="Edit Space" backTarget={backTarget}>
      <View style={styles.container}>
        {!space ? (
          <AppText variant="body">Loading space…</AppText>
        ) : (
          <>
            <AppText variant="body">Space name</AppText>
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Space name"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
            <AppText variant="body">Notes</AppText>
            <TextInput
              value={notes}
              onChangeText={setNotes}
              placeholder="Notes"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
              multiline
            />
            {error ? (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {error}
              </AppText>
            ) : null}
            <View style={styles.actions}>
              <AppButton title="Cancel" variant="secondary" onPress={() => router.back()} />
              <AppButton
                title={isSubmitting ? 'Saving…' : 'Save'}
                onPress={handleSubmit}
                disabled={isSubmitting}
              />
            </View>
          </>
        )}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
});
