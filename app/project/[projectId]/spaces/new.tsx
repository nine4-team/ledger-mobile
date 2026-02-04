import { useEffect, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../../src/components/Screen';
import { AppText } from '../../../../src/components/AppText';
import { AppButton } from '../../../../src/components/AppButton';
import { useAccountContextStore } from '../../../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../../../src/ui/styles/forms';
import { layout } from '../../../../src/ui';
import { createSpace } from '../../../../src/data/spacesService';
import { SpaceTemplate, subscribeToSpaceTemplates } from '../../../../src/data/spaceTemplatesService';

type SpaceParams = {
  projectId?: string;
};

export default function NewSpaceScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<SpaceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [name, setName] = useState('');
  const [notes, setNotes] = useState('');
  const [templates, setTemplates] = useState<SpaceTemplate[]>([]);
  const [selectedTemplate, setSelectedTemplate] = useState<SpaceTemplate | null>(null);
  const [checklists, setChecklists] = useState<SpaceTemplate['checklists']>([]);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!accountId) {
      setTemplates([]);
      return;
    }
    return subscribeToSpaceTemplates(accountId, (next) => {
      setTemplates(next);
    });
  }, [accountId]);

  const applyTemplate = (template: SpaceTemplate) => {
    setSelectedTemplate(template);
    setName(template.name);
    setNotes(template.notes ?? '');
    const normalized =
      template.checklists?.map((checklist) => ({
        ...checklist,
        items: checklist.items.map((item) => ({ ...item, isChecked: false })),
      })) ?? [];
    setChecklists(normalized);
  };

  const handleSubmit = async () => {
    if (!accountId || !projectId) {
      setError('Project context is missing.');
      return;
    }
    if (!name.trim()) {
      setError('Space name is required.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const spaceId = await createSpace(accountId, {
        name: name.trim(),
        notes: notes.trim() || null,
        projectId,
        checklists: checklists ?? null,
      });
      router.replace(`/project/${projectId}/spaces/${spaceId}`);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to create space.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const backTarget = projectId ? `/project/${projectId}/spaces` : undefined;

  return (
    <Screen title="New Space" backTarget={backTarget}>
      <View style={styles.container}>
        <AppText variant="body">Template</AppText>
        <View style={styles.templateRow}>
          {templates.length === 0 ? (
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              No templates available.
            </AppText>
          ) : null}
          {templates.map((template) => (
            <AppButton
              key={template.id}
              title={template.name}
              variant={selectedTemplate?.id === template.id ? 'primary' : 'secondary'}
              onPress={() => applyTemplate(template)}
            />
          ))}
        </View>
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
            title={isSubmitting ? 'Creating…' : 'Create space'}
            onPress={handleSubmit}
            disabled={isSubmitting}
          />
        </View>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  templateRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
});
