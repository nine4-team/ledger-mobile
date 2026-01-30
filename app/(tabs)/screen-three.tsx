import { ScrollView } from 'react-native';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { layout } from '../../src/ui';

export default function ScreenThree() {
  return (
    <Screen title="Screen Three">
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: layout.screenBodyTopMd.paddingTop }}
        showsVerticalScrollIndicator={false}
      >
        <AppText variant="body">This is Screen Three.</AppText>
      </ScrollView>
    </Screen>
  );
}
