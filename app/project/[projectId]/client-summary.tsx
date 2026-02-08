import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { ProjectClientSummaryReport } from '../../../src/screens/ProjectClientSummaryReport';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';

type ClientSummaryParams = {
  projectId?: string;
};

export default function ProjectClientSummaryScreen() {
  const params = useLocalSearchParams<ClientSummaryParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;

  if (!projectId) {
    return (
      <Screen title="Client Summary">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return <ProjectClientSummaryReport projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
