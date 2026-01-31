import { StyleSheet, View } from 'react-native';

import { AppText } from '../../src/components/AppText';
import { Screen } from '../../src/components/Screen';
import { useScreenTabs } from '../../src/components/ScreenTabs';
import { layout } from '../../src/ui';

export default function ProjectsScreen() {
  return (
    <Screen 
      title="Projects"
      tabs={[
        { key: 'items', label: 'Items', accessibilityLabel: 'Items tab' },
        { key: 'transactions', label: 'Transactions', accessibilityLabel: 'Transactions tab' },
        { key: 'spaces', label: 'Spaces', accessibilityLabel: 'Spaces tab' },
      ]}
      initialTabKey="items"
    >
      <ProjectsScreenContent />
    </Screen>
  );
}

function ProjectsScreenContent() {
  const screenTabs = useScreenTabs();
  const selectedKey = screenTabs?.selectedKey ?? 'items';

  if (selectedKey === 'items') {
    return (
      <View style={styles.placeholder}>
        <AppText variant="body">Project items go here.</AppText>
      </View>
    );
  }

  if (selectedKey === 'transactions') {
    return (
      <View style={styles.placeholder}>
        <AppText variant="body">Project transactions go here.</AppText>
      </View>
    );
  }

  return (
    <View style={styles.placeholder}>
      <AppText variant="body">Project spaces go here.</AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  placeholder: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
