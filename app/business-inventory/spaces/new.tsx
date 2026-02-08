import { StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { SpaceForm } from '../../../src/components/SpaceForm';
import type { SpaceFormValues } from '../../../src/components/SpaceForm';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { createSpace } from '../../../src/data/spacesService';
import { layout } from '../../../src/ui';

export default function NewBusinessInventorySpaceScreen() {
  const router = useRouter();
  const accountId = useAccountContextStore((store) => store.accountId);

  const backTarget = '/business-inventory/spaces';

  const handleSubmit = async (values: SpaceFormValues) => {
    if (!accountId) {
      throw new Error('Account context is missing.');
    }

    // Kick off the write — Firestore caches it locally for offline-first sync.
    // Don't await: the native SDK blocks until server ack, which hangs when offline.
    createSpace(accountId, {
      name: values.name,
      notes: values.notes || null,
      checklists: values.checklists ?? null,
      projectId: null,
    }).catch((err) => {
      console.warn('[spaces] create failed:', err);
    });

    router.replace(backTarget);
  };

  const handleCancel = () => {
    router.replace(backTarget);
  };

  return (
    <Screen title="New Space" backTarget={backTarget} hideMenu includeBottomInset={false}>
      <View style={styles.container}>
        <SpaceForm mode="create" onSubmit={handleSubmit} onCancel={handleCancel} />
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
