import { useMemo, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { FormActions } from '../../src/components/FormActions';
import { SpaceSelector } from '../../src/components/SpaceSelector';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { layout } from '../../src/ui';
import { createItem } from '../../src/data/itemsService';
import { getTransaction } from '../../src/data/transactionsService';
import { isCanonicalTransactionId } from '../../src/data/inventoryOperations';
import { saveLocalMedia } from '../../src/offline/media';

type NewItemParams = {
  scope?: string;
  projectId?: string;
  transactionId?: string;
  spaceId?: string;
  backTarget?: string;
};

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

export default function NewItemScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<NewItemParams>();
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const transactionId = Array.isArray(params.transactionId) ? params.transactionId[0] : params.transactionId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const initialSpaceId = Array.isArray(params.spaceId) ? params.spaceId[0] : params.spaceId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [name, setName] = useState('');
  const [source, setSource] = useState('');
  const [sku, setSku] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [projectPrice, setProjectPrice] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [imageUrls, setImageUrls] = useState<string[]>([]);
  const [imageUrl, setImageUrl] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [spaceId, setSpaceId] = useState<string | null>(initialSpaceId ?? null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=items';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=items`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const handleAddImage = async () => {
    let nextUrl = imageUrl.trim();
    if (!nextUrl && localImageUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localImageUri.trim(),
        mimeType: 'image/jpeg',
        ownerScope: `item:new`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    setImageUrls((prev) => [...prev, nextUrl].slice(0, 5));
    setImageUrl('');
    setLocalImageUri('');
  };

  const handleSubmit = async () => {
    if (!accountId) {
      setError('Account context is missing.');
      return;
    }
    if (!name.trim() && !sku.trim() && imageUrls.length === 0) {
      setError('Add a name, SKU, or at least one image.');
      return;
    }
    const purchasePriceCents = parseCurrency(purchasePrice);
    const projectPriceCents = parseCurrency(projectPrice);
    const qty = Math.max(1, Number.parseInt(quantity || '1', 10) || 1);
    setError(null);
    setIsSubmitting(true);
    try {
      let budgetCategoryId: string | null = null;
      if (transactionId) {
        const transaction = await getTransaction(accountId, transactionId, 'online');
        if (transaction && !isCanonicalTransactionId(transaction.id) && transaction.budgetCategoryId) {
          budgetCategoryId = transaction.budgetCategoryId;
        }
      }
      const payload = {
        name: name.trim(),
        sku: sku.trim() || null,
        source: source.trim() || null,
        status: status.trim() || null,
        purchasedBy: purchasedBy.trim() || null,
        purchasePriceCents,
        projectPriceCents,
        projectId: scope === 'project' ? projectId ?? null : null,
        transactionId: transactionId ?? null,
        budgetCategoryId,
        spaceId: spaceId ?? null,
        images: imageUrls.map((url, index) => ({
          url,
          kind: 'image' as const,
          ...(index === 0 ? { isPrimary: true } : {}),
        })),
      };
      for (let index = 0; index < qty; index += 1) {
        await createItem(accountId, payload);
      }
      router.replace(fallbackTarget);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to create item.';
      setError(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Screen title="New Item" backTarget={fallbackTarget} hideMenu includeBottomInset={false}>
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <AppText variant="body">Name</AppText>
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="Item name"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Source</AppText>
        <TextInput
          value={source}
          onChangeText={setSource}
          placeholder="Source"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">SKU</AppText>
        <TextInput
          value={sku}
          onChangeText={setSku}
          placeholder="SKU"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <View style={styles.row}>
          <View style={styles.half}>
            <AppText variant="body">Purchase price</AppText>
            <TextInput
              value={purchasePrice}
              onChangeText={setPurchasePrice}
              placeholder="$0.00"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
          </View>
          <View style={styles.half}>
            <AppText variant="body">Project price</AppText>
            <TextInput
              value={projectPrice}
              onChangeText={setProjectPrice}
              placeholder="$0.00"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
          </View>
        </View>
        <AppText variant="body">Quantity</AppText>
        <TextInput
          value={quantity}
          onChangeText={setQuantity}
          placeholder="1"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Purchased by</AppText>
        <TextInput
          value={purchasedBy}
          onChangeText={setPurchasedBy}
          placeholder="Purchased by"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Status</AppText>
        <TextInput
          value={status}
          onChangeText={setStatus}
          placeholder="needs_review / complete"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Space</AppText>
        <SpaceSelector
          projectId={scope === 'project' ? projectId ?? null : null}
          value={spaceId}
          onChange={setSpaceId}
          allowCreate={true}
          placeholder="Select space (optional)"
        />
        <AppText variant="body">Images</AppText>
        <TextInput
          value={imageUrl}
          onChangeText={setImageUrl}
          placeholder="Image URL"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <TextInput
          value={localImageUri}
          onChangeText={setLocalImageUri}
          placeholder="Local image URI (offline)"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppButton title="Add Image" onPress={handleAddImage} />
        {imageUrls.length ? (
          <AppText variant="caption">{imageUrls.length} image(s) added</AppText>
        ) : null}
        {error ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {error}
          </AppText>
        ) : null}
      </AppScrollView>

      <FormActions>
        <AppButton title="Cancel" variant="secondary" onPress={() => router.replace(fallbackTarget)} style={styles.actionButton} />
        <AppButton
          title={isSubmitting ? 'Adding…' : 'Add Item'}
          onPress={handleSubmit}
          disabled={isSubmitting}
          style={styles.actionButton}
        />
      </FormActions>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  row: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  half: {
    flex: 1,
  },
  actionButton: {
    flex: 1,
  },
});
