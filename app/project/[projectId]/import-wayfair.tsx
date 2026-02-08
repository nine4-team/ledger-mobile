import { useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';
import { ImportWayfairInvoice } from '../../../src/screens/ImportWayfairInvoice';

export default function ImportWayfairInvoiceRoute() {
  const { projectId } = useLocalSearchParams<{ projectId: string }>();
  if (!projectId) {
    return (
      <Screen title="Import Wayfair Invoice">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }
  return <ImportWayfairInvoice projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
