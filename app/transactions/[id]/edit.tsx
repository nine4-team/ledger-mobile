import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../../src/components/Screen';
import { AppText } from '../../../src/components/AppText';
import { AppButton } from '../../../src/components/AppButton';
import { AppScrollView } from '../../../src/components/AppScrollView';
import { FormField } from '../../../src/components/FormField';
import { FormActions } from '../../../src/components/FormActions';
import { TitledCard } from '../../../src/components/TitledCard';
import { MediaGallerySection } from '../../../src/components/MediaGallerySection';
import { useAccountContextStore } from '../../../src/auth/accountContextStore';
import { layout } from '../../../src/ui';
import { subscribeToTransaction, Transaction, updateTransaction } from '../../../src/data/transactionsService';
import { updateItem } from '../../../src/data/itemsService';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../../src/data/budgetCategoriesService';
import { isCanonicalInventorySaleTransaction } from '../../../src/data/inventoryOperations';
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../../src/data/scopeConfig';
import { ScopedItem, subscribeToScopedItems } from '../../../src/data/scopedListData';
import { saveLocalMedia, enqueueUpload, deleteLocalMediaByUrl } from '../../../src/offline/media';
import type { AttachmentRef, AttachmentKind } from '../../../src/offline/media';

type EditTransactionParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
};

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

export default function EditTransactionScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<EditTransactionParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const accountId = useAccountContextStore((store) => store.accountId);

  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Form state
  const [source, setSource] = useState('');
  const [transactionDate, setTransactionDate] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [reimbursementType, setReimbursementType] = useState('');
  const [notes, setNotes] = useState('');
  const [type, setType] = useState('');
  const [budgetCategoryId, setBudgetCategoryId] = useState('');
  const [hasEmailReceipt, setHasEmailReceipt] = useState(false);
  const [taxRatePct, setTaxRatePct] = useState('');
  const [subtotal, setSubtotal] = useState('');
  const [taxAmount, setTaxAmount] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});

  const selectedCategory = budgetCategories[budgetCategoryId];
  const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';
  const isCanonical = isCanonicalInventorySaleTransaction(transaction);

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (id) return `/transactions/${id}`;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=transactions';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=transactions`;
    return '/(tabs)/index';
  }, [backTarget, id, projectId, scope]);

  useEffect(() => {
    if (!accountId || !id) {
      setTransaction(null);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    const unsubscribe = subscribeToTransaction(accountId, id, (next) => {
      setTransaction(next);
      setIsLoading(false);
      if (next) {
        setSource(next.source ?? '');
        setTransactionDate(next.transactionDate ?? '');
        setAmount(typeof next.amountCents === 'number' ? (next.amountCents / 100).toFixed(2) : '');
        setStatus(next.status ?? '');
        setPurchasedBy(next.purchasedBy ?? '');
        setReimbursementType(next.reimbursementType ?? '');
        setNotes(next.notes ?? '');
        setType(next.transactionType ?? '');
        setBudgetCategoryId(next.budgetCategoryId ?? '');
        setHasEmailReceipt(!!next.hasEmailReceipt);
        setTaxRatePct(typeof next.taxRatePct === 'number' ? next.taxRatePct.toFixed(2) : '');
        setSubtotal(typeof next.subtotalCents === 'number' ? (next.subtotalCents / 100).toFixed(2) : '');
      }
    });
    return () => unsubscribe();
  }, [accountId, id]);

  useEffect(() => {
    if (!accountId) {
      setBudgetCategories({});
      return;
    }
    return subscribeToBudgetCategories(accountId, (next) => setBudgetCategories(mapBudgetCategories(next)));
  }, [accountId]);

  // Subscribe to items for category change propagation
  useEffect(() => {
    if (!accountId || !id || !scope) {
      setItems([]);
      return;
    }
    const scopeConfig =
      scope === 'inventory' ? createInventoryScopeConfig() : projectId ? createProjectScopeConfig(projectId) : null;
    if (!scopeConfig) {
      setItems([]);
      return;
    }
    const unsubscribe = subscribeToScopedItems(accountId, scopeConfig, (next) => {
      setItems(next);
    });
    return () => unsubscribe();
  }, [accountId, id, projectId, scope]);

  const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);

  // Receipt attachment handlers
  const handlePickReceiptAttachment = async (localUri: string, kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;
    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({ localUri, mimeType, ownerScope: `transaction:${id}`, persistCopy: true });
    const currentAttachments = transaction.receiptImages ?? [];
    const hasPrimary = currentAttachments.some((att) => att.isPrimary);
    const newAttachment: AttachmentRef = { url: result.attachmentRef.url, kind, isPrimary: !hasPrimary && kind === 'image' };
    const nextAttachments = [...currentAttachments, newAttachment].slice(0, 10);
    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments }).catch(err => {
      console.warn('[transactions] update receipt attachments failed:', err);
    });
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveReceiptAttachment = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;
    const nextAttachments = (transaction.receiptImages ?? []).filter((att) => att.url !== attachment.url);
    if (attachment.url.startsWith('offline://')) await deleteLocalMediaByUrl(attachment.url);
    if (!nextAttachments.some((att) => att.isPrimary) && nextAttachments.length > 0) {
      nextAttachments[0] = { ...nextAttachments[0], isPrimary: true };
    }
    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments }).catch(err => {
      console.warn('[transactions] remove receipt attachment failed:', err);
    });
  };

  const handleSetPrimaryReceiptAttachment = (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;
    const nextAttachments = (transaction.receiptImages ?? []).map((att) => ({ ...att, isPrimary: att.url === attachment.url }));
    updateTransaction(accountId, id, { receiptImages: nextAttachments, transactionImages: nextAttachments }).catch(err => {
      console.warn('[transactions] set primary receipt failed:', err);
    });
  };

  // Other image handlers
  const handlePickOtherImage = async (localUri: string, kind: AttachmentKind) => {
    if (!accountId || !id || !transaction) return;
    const mimeType = kind === 'pdf' ? 'application/pdf' : 'image/jpeg';
    const result = await saveLocalMedia({ localUri, mimeType, ownerScope: `transaction:${id}`, persistCopy: true });
    const currentImages = transaction.otherImages ?? [];
    const hasPrimary = currentImages.some((img) => img.isPrimary);
    const newImage: AttachmentRef = { url: result.attachmentRef.url, kind, isPrimary: !hasPrimary && kind === 'image' };
    const nextImages = [...currentImages, newImage].slice(0, 5);
    updateTransaction(accountId, id, { otherImages: nextImages }).catch(err => {
      console.warn('[transactions] update other images failed:', err);
    });
    await enqueueUpload({ mediaId: result.mediaId });
  };

  const handleRemoveOtherImage = async (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;
    const nextImages = (transaction.otherImages ?? []).filter((img) => img.url !== attachment.url);
    if (attachment.url.startsWith('offline://')) await deleteLocalMediaByUrl(attachment.url);
    if (!nextImages.some((img) => img.isPrimary) && nextImages.length > 0) {
      nextImages[0] = { ...nextImages[0], isPrimary: true };
    }
    updateTransaction(accountId, id, { otherImages: nextImages }).catch(err => {
      console.warn('[transactions] remove other image failed:', err);
    });
  };

  const handleSetPrimaryOtherImage = (attachment: AttachmentRef) => {
    if (!accountId || !id || !transaction) return;
    const nextImages = (transaction.otherImages ?? []).map((img) => ({ ...img, isPrimary: img.url === attachment.url }));
    updateTransaction(accountId, id, { otherImages: nextImages }).catch(err => {
      console.warn('[transactions] set primary other image failed:', err);
    });
  };

  const handleSave = () => {
    if (!accountId || !id) return;
    if (isCanonical) {
      setError('Canonical transactions cannot be edited.');
      return;
    }
    const amountCents = parseCurrency(amount);
    const hasReceipt = (transaction?.receiptImages?.length ?? 0) > 0;
    const hasSource = !!source.trim();
    const hasAmount = typeof amountCents === 'number' && amountCents > 0;
    if (!hasReceipt && (!hasSource || !hasAmount)) {
      setError('Add a receipt or provide source and amount.');
      return;
    }
    setError(null);

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
    const nextCategoryId = budgetCategoryId.trim() || null;
    const categoryChanged = nextCategoryId !== (transaction?.budgetCategoryId ?? null);
    updateTransaction(accountId, id, {
      source: source.trim() || null,
      transactionDate: transactionDate.trim() || null,
      amountCents: amountCents ?? null,
      status: status.trim() || null,
      purchasedBy: purchasedBy.trim() || null,
      reimbursementType: reimbursementType.trim() || null,
      notes: notes.trim() || null,
      transactionType: type.trim() || null,
      budgetCategoryId: nextCategoryId,
      hasEmailReceipt,
      taxRatePct: taxRateValue,
      subtotalCents,
    }).catch(err => {
      console.warn('[transactions] save failed:', err);
    });
    if (categoryChanged && nextCategoryId) {
      Promise.all(
        linkedItems.map((item) => updateItem(accountId, item.id, { budgetCategoryId: nextCategoryId }))
      ).catch(err => {
        console.warn('[transactions] category propagation failed:', err);
      });
    }
    router.replace(fallbackTarget);
  };

  if (!id) {
    return (
      <Screen title="Edit Transaction" backTarget={fallbackTarget} hideMenu>
        <View style={styles.container}>
          <AppText variant="body">Transaction not found.</AppText>
        </View>
      </Screen>
    );
  }

  return (
    <Screen title="Edit Transaction" backTarget={fallbackTarget} hideMenu includeBottomInset={false}>
      {isLoading ? (
        <View style={styles.container}>
          <AppText variant="body">Loading transaction...</AppText>
        </View>
      ) : !transaction ? (
        <View style={styles.container}>
          <AppText variant="body">Transaction not found.</AppText>
        </View>
      ) : (
        <>
          <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent}>
            <TitledCard title="Basic Information">
              <View style={styles.fieldGroup}>
                <FormField label="Source" value={source} onChangeText={setSource} placeholder="Source" />
                <FormField label="Date" value={transactionDate} onChangeText={setTransactionDate} placeholder="YYYY-MM-DD" />
                <FormField
                  label="Amount"
                  value={amount}
                  onChangeText={setAmount}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
              </View>
            </TitledCard>

            <TitledCard title="Classification">
              <View style={styles.fieldGroup}>
                <FormField label="Budget category" value={budgetCategoryId} onChangeText={setBudgetCategoryId} placeholder="Budget category id" />
                <FormField label="Status" value={status} onChangeText={setStatus} placeholder="Status" />
                <FormField label="Type" value={type} onChangeText={setType} placeholder="Transaction type" />
                <AppButton
                  title={hasEmailReceipt ? 'Email Receipt: Yes' : 'Email Receipt: No'}
                  variant="secondary"
                  onPress={() => setHasEmailReceipt((prev) => !prev)}
                />
              </View>
            </TitledCard>

            <TitledCard title="Payer">
              <View style={styles.fieldGroup}>
                <FormField label="Purchased by" value={purchasedBy} onChangeText={setPurchasedBy} placeholder="Purchased by" />
                <FormField label="Reimbursement type" value={reimbursementType} onChangeText={setReimbursementType} placeholder="Reimbursement type" />
              </View>
            </TitledCard>

            {itemizationEnabled ? (
              <TitledCard title="Tax & Itemization">
                <View style={styles.fieldGroup}>
                  <FormField
                    label="Tax rate (%)"
                    value={taxRatePct}
                    onChangeText={setTaxRatePct}
                    placeholder="0"
                    inputProps={{ keyboardType: 'numeric' }}
                  />
                  <FormField
                    label="Subtotal"
                    value={subtotal}
                    onChangeText={setSubtotal}
                    placeholder="$0.00"
                    inputProps={{ keyboardType: 'decimal-pad' }}
                  />
                  <FormField
                    label="Tax amount"
                    value={taxAmount}
                    onChangeText={setTaxAmount}
                    placeholder="$0.00"
                    inputProps={{ keyboardType: 'decimal-pad' }}
                  />
                </View>
              </TitledCard>
            ) : null}

            <TitledCard title="Receipts">
              <MediaGallerySection
                title="Receipts"
                attachments={transaction.receiptImages ?? []}
                maxAttachments={10}
                allowedKinds={['image', 'pdf']}
                onAddAttachment={handlePickReceiptAttachment}
                onRemoveAttachment={handleRemoveReceiptAttachment}
                onSetPrimary={handleSetPrimaryReceiptAttachment}
                emptyStateMessage="No receipts yet."
                pickerLabel="Add receipt"
                size="md"
                tileScale={1.5}
              />
            </TitledCard>

            <TitledCard title="Other Images">
              <MediaGallerySection
                title="Other Images"
                attachments={transaction.otherImages ?? []}
                maxAttachments={5}
                allowedKinds={['image']}
                onAddAttachment={handlePickOtherImage}
                onRemoveAttachment={handleRemoveOtherImage}
                onSetPrimary={handleSetPrimaryOtherImage}
                emptyStateMessage="No other images yet."
                pickerLabel="Add image"
                size="md"
                tileScale={1.5}
              />
            </TitledCard>

            <TitledCard title="Notes">
              <FormField
                label="Notes"
                value={notes}
                onChangeText={setNotes}
                placeholder="Add notes about this transaction..."
                inputProps={{ multiline: true, numberOfLines: 4, textAlignVertical: 'top' }}
              />
            </TitledCard>

            {error ? <AppText variant="caption" style={{ color: 'red' }}>{error}</AppText> : null}
          </AppScrollView>

          <FormActions>
            <AppButton
              title="Cancel"
              variant="secondary"
              onPress={() => router.back()}
              style={styles.actionButton}
            />
            <AppButton
              title="Save"
              onPress={handleSave}
              style={styles.actionButton}
            />
          </FormActions>
        </>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingTop: layout.screenBodyTopMd.paddingTop,
    gap: 18,
  },
  fieldGroup: {
    gap: 12,
  },
  actionButton: {
    flex: 1,
  },
});
