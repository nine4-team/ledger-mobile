import { useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { layout } from '../../src/ui';
import { useNetworkStatus } from '../../src/hooks/useNetworkStatus';
import { createProject } from '../../src/data/projectService';

export default function NewProjectScreen() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const { isOnline } = useNetworkStatus();
  const [name, setName] = useState('');
  const [clientName, setClientName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    if (!accountId) {
      setError('Select an account before creating a project.');
      return;
    }
    if (!name.trim() || !clientName.trim()) {
      setError('Project name and client name are required.');
      return;
    }
    if (!isOnline) {
      setError('Go online to create a project.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const result = await createProject({
        accountId,
        name: name.trim(),
        clientName: clientName.trim(),
      });
      router.replace(`/project/${result.projectId}?tab=items`);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to create project.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Screen title="New Project" backTarget="/(tabs)/index">
      <View style={styles.container}>
        <AppText variant="body">Project name</AppText>
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="Project name"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(theme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Client name</AppText>
        <TextInput
          value={clientName}
          onChangeText={setClientName}
          placeholder="Client name"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(theme, { padding: 12, radius: 10 })}
        />
        {error ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {error}
          </AppText>
        ) : null}
        <View style={styles.actions}>
          <AppButton title="Cancel" variant="secondary" onPress={() => router.back()} />
          <AppButton
            title={isSubmitting ? 'Creating…' : 'Create project'}
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
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
});
