import { useState } from 'react';
import { View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { SpaceDetailContent } from '../../../src/components/SpaceDetailContent';

type SpaceParams = {
  spaceId?: string;
};

export default function BusinessInventorySpaceDetailScreen() {
  const params = useLocalSearchParams<SpaceParams>();
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const [spaceName, setSpaceName] = useState('Space');
  const [menuVisible, setMenuVisible] = useState(false);

  if (!spaceId) {
    return (
      <Screen title="Space">
        <View style={{ flex: 1 }}>
          <AppText variant="body">Space not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen
      title={spaceName}
      backTarget="/business-inventory/spaces"
      onPressMenu={() => setMenuVisible(true)}
      includeBottomInset={false}
    >
      <SpaceDetailContent
        scope={{ projectId: null, spaceId }}
        onSpaceNameChange={setSpaceName}
        spaceMenuVisible={menuVisible}
        onCloseSpaceMenu={() => setMenuVisible(false)}
      />
    </Screen>
  );
}
