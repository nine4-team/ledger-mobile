import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { ProjectPropertyManagementReport } from '../../../src/screens/ProjectPropertyManagementReport';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';

type PropertyManagementParams = {
  projectId?: string;
};

export default function ProjectPropertyManagementScreen() {
  const params = useLocalSearchParams<PropertyManagementParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;

  if (!projectId) {
    return (
      <Screen title="Property Management">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return <ProjectPropertyManagementReport projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
