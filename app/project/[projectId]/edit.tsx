import { useEffect, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { useUIKitTheme } from '../../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../../src/ui/styles/forms';
import { layout } from '../../../src/ui';
import { Project, subscribeToProject, updateProject } from '../../../src/data/projectService';

type EditParams = {
  projectId?: string;
};

export default function EditProjectScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<EditParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useUIKitTheme();
  const [project, setProject] = useState<Project | null>(null);
  const [name, setName] = useState('');
  const [clientName, setClientName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!accountId || !projectId) {
      setProject(null);
      return;
    }
    const unsubscribe = subscribeToProject(accountId, projectId, (next) => {
      setProject(next);
      setName(next?.name ?? '');
      setClientName(next?.clientName ?? '');
    });
    return () => unsubscribe();
  }, [accountId, projectId]);

  const handleSubmit = async () => {
    if (!accountId || !projectId) return;
    if (!name.trim() || !clientName.trim()) {
      setError('Project name and client name are required.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      await updateProject(accountId, projectId, {
        name: name.trim(),
        clientName: clientName.trim(),
      });
      router.replace(`/project/${projectId}?tab=items`);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to update project.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const backTarget = projectId ? `/project/${projectId}?tab=items` : undefined;

  if (!projectId) {
    return (
      <Screen title="Edit Project" backTarget={backTarget}>
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen title="Edit Project" backTarget={backTarget}>
      <View style={styles.container}>
        {!project ? (
          <AppText variant="body">Loading project…</AppText>
        ) : (
          <>
            <AppText variant="body">Project name</AppText>
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Project name"
              placeholderTextColor={theme.text.secondary}
              style={getTextInputStyle(theme, { padding: 12, radius: 10 })}
            />
            <AppText variant="body">Client name</AppText>
            <TextInput
              value={clientName}
              onChangeText={setClientName}
              placeholder="Client name"
              placeholderTextColor={theme.text.secondary}
              style={getTextInputStyle(theme, { padding: 12, radius: 10 })}
            />
            {error ? (
              <AppText variant="caption" style={{ color: theme.text.secondary }}>
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
