import { View, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { ProjectInvoiceReport } from '../../../src/screens/ProjectInvoiceReport';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';

type InvoiceParams = {
  projectId?: string;
};

export default function ProjectInvoiceScreen() {
  const params = useLocalSearchParams<InvoiceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;

  if (!projectId) {
    return (
      <Screen title="Invoice Report">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }

  return <ProjectInvoiceReport projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
