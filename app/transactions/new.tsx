import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { FormActions } from '../../src/components/FormActions';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { layout } from '../../src/ui';
import { createTransaction } from '../../src/data/transactionsService';
import { saveLocalMedia } from '../../src/offline/media';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../src/data/budgetCategoriesService';
import { moveItemToReturnTransaction } from '../../src/data/returnFlowService';

type NewTransactionParams = {
  scope?: string;
  projectId?: string;
  backTarget?: string;
  transactionType?: string;
  linkItemIds?: string;
  linkItemFromTransactionId?: string;
};

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

export default function NewTransactionScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<NewTransactionParams>();
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const transactionType = Array.isArray(params.transactionType) ? params.transactionType[0] : params.transactionType;
  const linkItemIds = Array.isArray(params.linkItemIds) ? params.linkItemIds[0] : params.linkItemIds;
  const linkItemFromTransactionId = Array.isArray(params.linkItemFromTransactionId) ? params.linkItemFromTransactionId[0] : params.linkItemFromTransactionId;
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [source, setSource] = useState('');
  const [transactionDate, setTransactionDate] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [reimbursementType, setReimbursementType] = useState('');
  const [notes, setNotes] = useState('');
  const [type, setType] = useState(transactionType ?? '');
  const [budgetCategoryId, setBudgetCategoryId] = useState('');
  const [hasEmailReceipt, setHasEmailReceipt] = useState(false);
  const [receipts, setReceipts] = useState<string[]>([]);
  const [images, setImages] = useState<string[]>([]);
  const [taxRatePct, setTaxRatePct] = useState('');
  const [subtotal, setSubtotal] = useState('');
  const [taxAmount, setTaxAmount] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [receiptUrl, setReceiptUrl] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [localReceiptUri, setLocalReceiptUri] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [error, setError] = useState<string | null>(null);

  const selectedCategory = budgetCategories[budgetCategoryId];
  const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => setBudgetCategories(mapBudgetCategories(next)));
  }, [accountId]);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=transactions';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=transactions`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const handleAddReceipt = async () => {
    let nextUrl = receiptUrl.trim();
    if (!nextUrl && localReceiptUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localReceiptUri.trim(),
        mimeType: 'application/pdf',
        ownerScope: `transaction:new`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    setReceipts((prev) => [...prev, nextUrl].slice(0, 5));
    setReceiptUrl('');
    setLocalReceiptUri('');
  };

  const handleAddImage = async () => {
    let nextUrl = imageUrl.trim();
    if (!nextUrl && localImageUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localImageUri.trim(),
        mimeType: 'image/jpeg',
        ownerScope: `transaction:new`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    setImages((prev) => [...prev, nextUrl].slice(0, 5));
    setImageUrl('');
    setLocalImageUri('');
  };

  const handleSubmit = () => {
    if (!accountId) {
      setError('Account context is missing.');
      return;
    }
    const amountCents = parseCurrency(amount);
    const hasReceipt = receipts.length > 0;
    const hasSource = !!source.trim();
    const hasAmount = typeof amountCents === 'number' && amountCents > 0;
    if (!hasReceipt && (!hasSource || !hasAmount)) {
      setError('Add a receipt or provide source and amount.');
      return;
    }
    if (!budgetCategoryId.trim()) {
      setError('Budget category id is required.');
      return;
    }
    let subtotalCents: number | null = null;
    let taxRateValue: number | null = null;
    if (itemizationEnabled) {
      const amountValue = typeof amountCents === 'number' ? amountCents : null;
      if (amountValue != null) {
        const parsedSubtotal = parseCurrency(subtotal);
        const parsedTaxAmount = parseCurrency(taxAmount);
        const parsedTaxRate = Number.parseFloat(taxRatePct);
        if (Number.isFinite(parsedTaxRate) && parsedTaxRate > 0) {
          const rate = parsedTaxRate / 100;
          subtotalCents = Math.round(amountValue / (1 + rate));
          taxRateValue = parsedTaxRate;
        } else if (parsedSubtotal != null && parsedSubtotal > 0 && parsedSubtotal <= amountValue) {
          subtotalCents = parsedSubtotal;
          const taxCents = amountValue - parsedSubtotal;
          taxRateValue = taxCents > 0 ? (taxCents / parsedSubtotal) * 100 : 0;
        } else if (parsedTaxAmount != null && parsedTaxAmount >= 0 && parsedTaxAmount < amountValue) {
          subtotalCents = amountValue - parsedTaxAmount;
          taxRateValue = subtotalCents > 0 ? (parsedTaxAmount / subtotalCents) * 100 : 0;
        }
      }
    }
    setError(null);
    const newTxId = createTransaction(accountId, {
      source: source.trim(),
      transactionDate: transactionDate.trim() || null,
      amountCents,
      status: status.trim() || null,
      purchasedBy: purchasedBy.trim() || null,
      reimbursementType: reimbursementType.trim() || null,
      notes: notes.trim() || null,
      transactionType: type.trim() || null,
      budgetCategoryId: budgetCategoryId.trim(),
      hasEmailReceipt,
      taxRatePct: taxRateValue,
      subtotalCents,
      receiptImages: receipts.map((url) => ({ url, kind: url.endsWith('.pdf') ? 'pdf' : 'image' })),
      otherImages: images.map((url) => ({ url, kind: 'image' })),
      projectId: scope === 'project' ? projectId ?? null : null,
    });

    // Link items from the return flow (fire-and-forget per offline-first rules)
    if (linkItemIds) {
      const itemIds = linkItemIds.split(',').filter(Boolean);
      for (const itemId of itemIds) {
        moveItemToReturnTransaction({
          accountId,
          itemId,
          fromTransactionId: linkItemFromTransactionId || null,
          returnTransactionId: newTxId,
          fromProjectId: projectId ?? null,
          toProjectId: projectId ?? null,
        });
      }
    }

    router.replace(fallbackTarget);
  };

  return (
    <Screen title="New Transaction" backTarget={fallbackTarget} hideMenu includeBottomInset={false}>
      <AppScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <AppText variant="body">Source</AppText>
        <TextInput
          value={source}
          onChangeText={setSource}
          placeholder="Source"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Transaction date</AppText>
        <TextInput
          value={transactionDate}
          onChangeText={setTransactionDate}
          placeholder="YYYY-MM-DD"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Amount</AppText>
        <TextInput
          value={amount}
          onChangeText={setAmount}
          placeholder="$0.00"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Budget category id</AppText>
        <TextInput
          value={budgetCategoryId}
          onChangeText={setBudgetCategoryId}
          placeholder="Budget category id"
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
        <AppText variant="body">Purchased by</AppText>
        <TextInput
          value={purchasedBy}
          onChangeText={setPurchasedBy}
          placeholder="Purchased by"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Reimbursement type</AppText>
        <TextInput
          value={reimbursementType}
          onChangeText={setReimbursementType}
          placeholder="Reimbursement type"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Transaction type</AppText>
        <TextInput
          value={type}
          onChangeText={setType}
          placeholder="Transaction type"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppText variant="body">Notes</AppText>
        <TextInput
          value={notes}
          onChangeText={setNotes}
          placeholder="Notes"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
          multiline
        />
        <View style={styles.row}>
          <AppButton
            title={hasEmailReceipt ? 'Email receipt: yes' : 'Email receipt: no'}
            variant="secondary"
            onPress={() => setHasEmailReceipt((prev) => !prev)}
          />
        </View>
        {itemizationEnabled ? (
          <>
            <AppText variant="body">Tax rate (%)</AppText>
            <TextInput
              value={taxRatePct}
              onChangeText={setTaxRatePct}
              placeholder="0"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
              keyboardType="numeric"
            />
            <AppText variant="body">Subtotal</AppText>
            <TextInput
              value={subtotal}
              onChangeText={setSubtotal}
              placeholder="$0.00"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
            <AppText variant="body">Tax amount</AppText>
            <TextInput
              value={taxAmount}
              onChangeText={setTaxAmount}
              placeholder="$0.00"
              placeholderTextColor={theme.colors.textSecondary}
              style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
            />
          </>
        ) : null}
        <AppText variant="body">Receipts</AppText>
        <TextInput
          value={receiptUrl}
          onChangeText={setReceiptUrl}
          placeholder="Receipt URL"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <TextInput
          value={localReceiptUri}
          onChangeText={setLocalReceiptUri}
          placeholder="Local receipt URI (offline)"
          placeholderTextColor={theme.colors.textSecondary}
          style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
        />
        <AppButton title="Add Receipt" onPress={handleAddReceipt} />
        <AppText variant="body">Other images</AppText>
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
        {error ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {error}
          </AppText>
        ) : null}
      </AppScrollView>

      <FormActions>
        <AppButton title="Cancel" variant="secondary" onPress={() => router.replace(fallbackTarget)} style={styles.actionButton} />
        <AppButton
          title="Add Transaction"
          onPress={handleSubmit}
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
  actionButton: {
    flex: 1,
  },
});
