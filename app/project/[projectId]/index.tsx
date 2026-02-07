import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { ProjectShell } from '../../../src/screens/ProjectShell';

type ProjectParams = {
  projectId?: string;
  tab?: string;
};

export default function ProjectShellRoute() {
  const params = useLocalSearchParams<ProjectParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const tab = Array.isArray(params.tab) ? params.tab[0] : params.tab;

  if (!projectId) {
    return (
      <Screen title="Project">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  const initialTabKey =
    tab === 'budget' || tab === 'transactions' || tab === 'spaces' || tab === 'items' ? tab : 'budget';

  return <ProjectShell projectId={projectId} initialTabKey={initialTabKey} />;
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
  },
});
