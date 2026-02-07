import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { ProjectBudgetForm } from '../../../src/screens/ProjectBudgetForm';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';

type BudgetParams = {
  projectId?: string;
};

export default function ProjectBudgetScreen() {
  const params = useLocalSearchParams<BudgetParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const router = useRouter();

  const backTarget = projectId ? `/project/${projectId}?tab=items` : undefined;

  if (!projectId) {
    return (
      <Screen title="Project Budget" backTarget={backTarget}>
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return <ProjectBudgetForm projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
