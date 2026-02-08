import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../../src/components/Screen';
import { AppText } from '../../../../src/components/AppText';
import { SpaceForm } from '../../../../src/components/SpaceForm';
import type { SpaceFormValues } from '../../../../src/components/SpaceForm';
import { useAccountContextStore } from '../../../../src/auth/accountContextStore';
import { layout } from '../../../../src/ui';
import { Space, subscribeToSpace, updateSpace } from '../../../../src/data/spacesService';

type EditSpaceParams = {
  spaceId?: string;
};

export default function EditBusinessInventorySpaceScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<EditSpaceParams>();
  const spaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const [space, setSpace] = useState<Space | null>(null);

  const backTarget = spaceId ? `/business-inventory/spaces/${spaceId}` : '/business-inventory/spaces';

  useEffect(() => {
    if (!accountId || !spaceId) {
      setSpace(null);
      return;
    }
    const unsubscribe = subscribeToSpace(accountId, spaceId, (next) => {
      setSpace(next);
    });
    return () => unsubscribe();
  }, [accountId, spaceId]);

  const handleSubmit = async (values: SpaceFormValues) => {
    if (!accountId) {
      throw new Error('Account context is missing.');
    }
    if (!spaceId) {
      throw new Error('Space ID is missing.');
    }

    await updateSpace(accountId, spaceId, {
      name: values.name,
      notes: values.notes || null,
    });

    router.replace(backTarget);
  };

  const handleCancel = () => {
    router.replace(backTarget);
  };

  return (
    <Screen title="Edit Space" backTarget={backTarget} hideMenu includeBottomInset={false}>
      <View style={styles.container}>
        {!space ? (
          <AppText variant="body">Loading space…</AppText>
        ) : (
          <SpaceForm
            mode="edit"
            initialValues={{
              name: space.name,
              notes: space.notes ?? '',
            }}
            onSubmit={handleSubmit}
            onCancel={handleCancel}
          />
        )}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
});
