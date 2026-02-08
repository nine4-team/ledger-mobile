import { useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { layout } from '../../../src/ui';
import { ImportAmazonInvoice } from '../../../src/screens/ImportAmazonInvoice';

export default function ImportAmazonInvoiceRoute() {
  const { projectId } = useLocalSearchParams<{ projectId: string }>();
  if (!projectId) {
    return (
      <Screen title="Import Amazon Invoice">
        <View style={styles.container}>
          <AppText variant="body">Project not found.</AppText>
        </View>
      </Screen>
    );
  }
  return <ImportAmazonInvoice projectId={projectId} />;
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
