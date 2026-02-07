import { useEffect, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { AppText } from './AppText';
import { AppButton } from './AppButton';
import { MultiSelectPicker } from './MultiSelectPicker';
import type { MultiSelectPickerOption } from './MultiSelectPicker';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
import { subscribeToSpaceTemplates, SpaceTemplate } from '../data/spaceTemplatesService';
import { useAccountContextStore } from '../auth/accountContextStore';
import type { Checklist } from '../data/spacesService';

export type SpaceFormMode = 'create' | 'edit';

export type SpaceFormValues = {
  name: string;
  notes: string;
  checklists?: Checklist[] | null;
};

export type SpaceFormProps = {
  mode: SpaceFormMode;
  initialValues?: SpaceFormValues;
  onSubmit: (values: SpaceFormValues) => Promise<void>;
  onCancel: () => void;
};

export function SpaceForm({ mode, initialValues, onSubmit, onCancel }: SpaceFormProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const accountId = useAccountContextStore((store) => store.accountId);
  const [name, setName] = useState(initialValues?.name ?? '');
  const [notes, setNotes] = useState(initialValues?.notes ?? '');
  const [checklists, setChecklists] = useState<Checklist[] | null>(initialValues?.checklists ?? null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [templates, setTemplates] = useState<SpaceTemplate[]>([]);
  const [selectedTemplateId, setSelectedTemplateId] = useState<string>('');

  // Subscribe to templates on mount (only for create mode)
  useEffect(() => {
    if (mode !== 'create' || !accountId) {
      setTemplates([]);
      return;
    }
    const unsubscribe = subscribeToSpaceTemplates(accountId, (next) => {
      // Filter to active templates only and sort by order
      const activeTemplates = next
        .filter((t) => !t.isArchived)
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
      setTemplates(activeTemplates);
    });
    return () => unsubscribe();
  }, [mode, accountId]);

  // Handle template selection
  const handleTemplateChange = (templateId: string) => {
    setSelectedTemplateId(templateId);
    if (!templateId) {
      // "Start blank" option
      setName('');
      setNotes('');
      setChecklists(null);
      return;
    }

    const template = templates.find((t) => t.id === templateId);
    if (!template) return;

    // Prefill form values
    setName(template.name?.trim() || '');
    setNotes(template.notes?.trim() || '');

    // Normalize checklists: force all items to isChecked = false
    if (template.checklists && template.checklists.length > 0) {
      const normalizedChecklists = template.checklists.map((checklist) => ({
        ...checklist,
        items: checklist.items.map((item) => ({ ...item, isChecked: false })),
      }));
      setChecklists(normalizedChecklists);
    } else {
      setChecklists(null);
    }
  };

  const handleSubmit = async () => {
    const trimmedName = name.trim();
    if (!trimmedName) {
      setError('Space name is required.');
      return;
    }

    setError(null);
    setIsSubmitting(true);
    try {
      await onSubmit({
        name: trimmedName,
        notes: notes.trim(),
        checklists,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to save space.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const templateOptions: MultiSelectPickerOption<string>[] = [
    { value: '', label: 'Start blank' },
    ...templates.map((template) => ({
      value: template.id,
      label: template.name,
    })),
  ];

  return (
    <View style={styles.container}>
      {mode === 'create' && templates.length > 0 ? (
        <MultiSelectPicker
          label="Template"
          value={selectedTemplateId}
          options={templateOptions}
          onChange={(next) => handleTemplateChange(next as string)}
          multiSelect={false}
          helperText="Select a template to prefill, or start blank"
          accessibilityLabel="Space template picker"
        />
      ) : null}

      <AppText variant="body">Name *</AppText>
      <TextInput
        value={name}
        onChangeText={(text) => {
          setName(text);
          if (error) setError(null);
        }}
        placeholder="Space name"
        placeholderTextColor={theme.colors.textSecondary}
        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        autoFocus={mode === 'create'}
      />

      <AppText variant="body">Notes</AppText>
      <TextInput
        value={notes}
        onChangeText={setNotes}
        placeholder="Optional notes"
        placeholderTextColor={theme.colors.textSecondary}
        style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        multiline
        numberOfLines={4}
        textAlignVertical="top"
      />

      {error ? (
        <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
          {error}
        </AppText>
      ) : null}

      <View style={styles.actions}>
        <AppButton title="Cancel" variant="secondary" onPress={onCancel} disabled={isSubmitting} />
        <AppButton
          title={isSubmitting ? 'Saving…' : mode === 'create' ? 'Create space' : 'Save changes'}
          onPress={handleSubmit}
          disabled={isSubmitting}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
});
