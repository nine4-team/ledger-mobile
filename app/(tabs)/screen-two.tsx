import { ScrollView } from 'react-native';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { layout } from '../../src/ui';

export default function ScreenTwo() {
  return (
    <Screen title="Screen Two">
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: layout.screenBodyTopMd.paddingTop }}
        showsVerticalScrollIndicator={false}
      >
        <AppText variant="body">This is Screen Two.</AppText>
      </ScrollView>
    </Screen>
  );
}
