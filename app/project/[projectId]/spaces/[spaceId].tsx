import { useState } from 'react';
import { View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { Screen } from '../../../../src/components/Screen';
import { AppText } from '../../../../src/components/AppText';
import { SpaceDetailContent } from '../../../../src/components/SpaceDetailContent';

type SpaceParams = {
  projectId?: string;
  spaceId?: string;
};

export default function ProjectSpaceDetailScreen() {
  const params = useLocalSearchParams<SpaceParams>();
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const [spaceName, setSpaceName] = useState('Space');
  const [menuVisible, setMenuVisible] = useState(false);

  if (!projectId || !spaceId) {
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
      backTarget={`/project/${projectId}?tab=spaces`}
      onPressMenu={() => setMenuVisible(true)}
    >
      <SpaceDetailContent
        scope={{ projectId, spaceId }}
        onSpaceNameChange={setSpaceName}
        spaceMenuVisible={menuVisible}
        onCloseSpaceMenu={() => setMenuVisible(false)}
      />
    </Screen>
  );
}
