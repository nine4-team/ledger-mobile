import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { ProjectShell } from '../../../src/screens/ProjectShell';

type ProjectParams = {
  projectId?: string;
};

export default function ProjectSpacesRoute() {
  const params = useLocalSearchParams<ProjectParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;

  if (!projectId) {
    return (
      <Screen title="Project">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return <ProjectShell projectId={projectId} initialTabKey="spaces" />;
}

const styles = StyleSheet.create({
  container: {
    padding: 16,
  },
});
