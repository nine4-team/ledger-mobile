import { StyleSheet, View } from 'react-native';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { layout } from '../../src/ui';

export default function ScreenTwo() {
  return (
    <Screen
      title="Inventory"
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'transactions', label: 'Transactions', accessibilityLabel: 'Transactions tab' },
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
      ]}
      initialTabKey="items"
    >
      <InventoryScreenContent />
    </Screen>
  );
}

function InventoryScreenContent() {
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';

  if (selectedKey === 'items') {
    return (
      <View style={styles.placeholder}>
        <AppText variant="body">Inventory items go here.</AppText>
      </View>
    );
  }

  if (selectedKey === 'transactions') {
    return (
      <View style={styles.placeholder}>
        <AppText variant="body">Inventory transactions go here.</AppText>
      </View>
    );
  }

  return (
    <View style={styles.placeholder}>
      <AppText variant="body">Inventory spaces go here.</AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
