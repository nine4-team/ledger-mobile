import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, StyleSheet, TextInput, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { ItemCard } from '../../src/components/ItemCard';
import { GroupedItemCard } from '../../src/components/GroupedItemCard';
import { SegmentedControl } from '../../src/components/SegmentedControl';
import { layout } from '../../src/ui';
import { useProjectContextStore } from '../../src/data/projectContextStore';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { getTextInputStyle } from '../../src/ui/styles/forms';
import { createInventoryScopeConfig, createProjectScopeConfig } from '../../src/data/scopeConfig';
import { ProjectSummary, ScopedItem, subscribeToProjects, subscribeToScopedItems } from '../../src/data/scopedListData';
import { Item, listItemsByProject, updateItem } from '../../src/data/itemsService';
import { saveLocalMedia } from '../../src/offline/media';
import { mapBudgetCategories, subscribeToBudgetCategories } from '../../src/data/budgetCategoriesService';
import { deleteTransaction, subscribeToTransaction, Transaction, updateTransaction } from '../../src/data/transactionsService';
import { isCanonicalTransactionId } from '../../src/data/inventoryOperations';

type TransactionDetailParams = {
  id?: string;
  scope?: string;
  projectId?: string;
  backTarget?: string;
  listStateKey?: string;
};

type ItemPickerTab = 'suggested' | 'project' | 'outside';

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

export default function TransactionDetailScreen() {
  const router = useRouter();
  const { setProjectId } = useProjectContextStore();
  const accountId = useAccountContextStore((store) => store.accountId);
  const params = useLocalSearchParams<TransactionDetailParams>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scope = Array.isArray(params.scope) ? params.scope[0] : params.scope;
  const projectId = Array.isArray(params.projectId) ? params.projectId[0] : params.projectId;
  const backTarget = Array.isArray(params.backTarget) ? params.backTarget[0] : params.backTarget;
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [transaction, setTransaction] = useState<Transaction | null>(null);
  const [items, setItems] = useState<ScopedItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isEditing, setIsEditing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [source, setSource] = useState('');
  const [transactionDate, setTransactionDate] = useState('');
  const [amount, setAmount] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [reimbursementType, setReimbursementType] = useState('');
  const [notes, setNotes] = useState('');
  const [type, setType] = useState('');
  const [budgetCategoryId, setBudgetCategoryId] = useState('');
  const [budgetCategories, setBudgetCategories] = useState<Record<string, { name: string; metadata?: any }>>({});
  const [hasEmailReceipt, setHasEmailReceipt] = useState(false);
  const [taxRatePct, setTaxRatePct] = useState('');
  const [subtotal, setSubtotal] = useState('');
  const [taxAmount, setTaxAmount] = useState('');
  const [receiptUrl, setReceiptUrl] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [localReceiptUri, setLocalReceiptUri] = useState('');
  const [localImageUri, setLocalImageUri] = useState('');
  const [isPickingItems, setIsPickingItems] = useState(false);
  const [pickerTab, setPickerTab] = useState<ItemPickerTab>('suggested');
  const [pickerQuery, setPickerQuery] = useState('');
  const [pickerSelectedIds, setPickerSelectedIds] = useState<string[]>([]);
  const [outsideItems, setOutsideItems] = useState<Item[]>([]);
  const [outsideLoading, setOutsideLoading] = useState(false);
  const [outsideError, setOutsideError] = useState<string | null>(null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);

  useEffect(() => {
    if (scope === 'project' && projectId) {
      setProjectId(projectId);
    }
  }, [projectId, scope, setProjectId]);

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
        setAmount(
          typeof next.amountCents === 'number' ? (next.amountCents / 100).toFixed(2) : ''
        );
        setStatus(next.status ?? '');
        setPurchasedBy(next.purchasedBy ?? '');
        setReimbursementType(next.reimbursementType ?? '');
        setNotes(next.notes ?? '');
        setType(next.type ?? '');
        setBudgetCategoryId(next.budgetCategoryId ?? '');
        setHasEmailReceipt(!!next.hasEmailReceipt);
        setTaxRatePct(
          typeof next.taxRatePct === 'number' ? next.taxRatePct.toFixed(2) : ''
        );
        setSubtotal(
          typeof next.subtotalCents === 'number' ? (next.subtotalCents / 100).toFixed(2) : ''
        );
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

  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      return;
    }
    return subscribeToProjects(accountId, (next) => setProjects(next));
  }, [accountId]);

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

  const fallbackTarget = useMemo(() => {
    if (backTarget) return backTarget;
    if (scope === 'inventory') return '/(tabs)/screen-two?tab=transactions';
    if (scope === 'project' && projectId) return `/project/${projectId}?tab=transactions`;
    return '/(tabs)/index';
  }, [backTarget, projectId, scope]);

  const handleBack = () => {
    if (router.canGoBack()) {
      router.back();
      return;
    }
    router.replace(fallbackTarget);
  };

  const isCanonical = isCanonicalTransactionId(id ?? '');
  const linkedItems = useMemo(() => items.filter((item) => item.transactionId === id), [id, items]);
  const selectedCategory = budgetCategories[budgetCategoryId];
  const itemizationEnabled = selectedCategory?.metadata?.categoryType === 'itemized';
  const normalizedSource = transaction?.source?.trim().toLowerCase() ?? '';

  const suggestedItems = useMemo(() => {
    if (!normalizedSource) return [];
    return items.filter((item) => {
      const itemSource = item.source?.trim().toLowerCase() ?? '';
      return itemSource === normalizedSource && !item.transactionId;
    });
  }, [items, normalizedSource]);

  const projectItems = useMemo(() => (projectId ? items : []), [items, projectId]);

  const filteredSuggestedItems = useMemo(() => {
    const needle = pickerQuery.trim().toLowerCase();
    if (!needle) return suggestedItems;
    return suggestedItems.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [pickerQuery, suggestedItems]);

  const filteredProjectItems = useMemo(() => {
    const needle = pickerQuery.trim().toLowerCase();
    if (!needle) return projectItems;
    return projectItems.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [pickerQuery, projectItems]);

  const filteredOutsideItems = useMemo(() => {
    const needle = pickerQuery.trim().toLowerCase();
    if (!needle) return outsideItems;
    return outsideItems.filter((item) => {
      const label = item.name?.toLowerCase() ?? item.description?.toLowerCase() ?? '';
      return label.includes(needle);
    });
  }, [pickerQuery, outsideItems]);

  const activePickerItems = useMemo(() => {
    if (pickerTab === 'suggested') return filteredSuggestedItems;
    if (pickerTab === 'project') return filteredProjectItems;
    return filteredOutsideItems;
  }, [filteredOutsideItems, filteredProjectItems, filteredSuggestedItems, pickerTab]);

  const pickerGroups = useMemo(() => {
    const groups = new Map<string, ScopedItem[]>();
    activePickerItems.forEach((item) => {
      const label = item.name?.trim() || item.description?.trim() || 'Item';
      const key = label.toLowerCase();
      const list = groups.get(key) ?? [];
      list.push(item as ScopedItem);
      groups.set(key, list);
    });
    return Array.from(groups.entries());
  }, [activePickerItems]);

  const pickerTabOptions = useMemo(() => {
    const options: Array<{ value: ItemPickerTab; label: string; accessibilityLabel?: string }> = [
      { value: 'suggested', label: 'Suggested', accessibilityLabel: 'Suggested items tab' },
    ];
    if (projectId) options.push({ value: 'project', label: 'Project', accessibilityLabel: 'Project items tab' });
    options.push({ value: 'outside', label: 'Outside', accessibilityLabel: 'Outside items tab' });
    return options;
  }, [projectId]);

  const loadOutsideItems = useCallback(async () => {
    if (!accountId) return;
    setOutsideLoading(true);
    setOutsideError(null);
    try {
      const currentProjectId = projectId ?? null;
      const otherProjects = projects.filter((project) => project.id !== currentProjectId);
      const requests: Promise<Item[]>[] = [];
      if (scope === 'project') {
        requests.push(listItemsByProject(accountId, null, { mode: 'offline' }));
      }
      requests.push(...otherProjects.map((project) => listItemsByProject(accountId, project.id, { mode: 'offline' })));
      const results = await Promise.all(requests);
      const flattened = results.flat().filter((item) => item.projectId !== currentProjectId);
      const unique = new Map(flattened.map((item) => [item.id, item]));
      setOutsideItems(Array.from(unique.values()));
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unable to load outside items.';
      setOutsideError(message);
    } finally {
      setOutsideLoading(false);
    }
  }, [accountId, projectId, projects, scope]);

  useEffect(() => {
    if (!isPickingItems || pickerTab !== 'outside') return;
    void loadOutsideItems();
  }, [isPickingItems, pickerTab, loadOutsideItems]);

  const handleSave = async () => {
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
    await updateTransaction(accountId, id, {
      source: source.trim() || null,
      transactionDate: transactionDate.trim() || null,
      amountCents: amountCents ?? null,
      status: status.trim() || null,
      purchasedBy: purchasedBy.trim() || null,
      reimbursementType: reimbursementType.trim() || null,
      notes: notes.trim() || null,
      type: type.trim() || null,
      budgetCategoryId: nextCategoryId,
      hasEmailReceipt,
      taxRatePct: taxRateValue,
      subtotalCents,
    });
    if (categoryChanged && nextCategoryId) {
      await Promise.all(
        linkedItems.map((item) => updateItem(accountId, item.id, { inheritedBudgetCategoryId: nextCategoryId }))
      );
    }
    setIsEditing(false);
  };

  const handleAddReceipt = async () => {
    if (!accountId || !id || !transaction) return;
    let nextUrl = receiptUrl.trim();
    if (!nextUrl && localReceiptUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localReceiptUri.trim(),
        mimeType: 'application/pdf',
        ownerScope: `transaction:${id}`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    const nextReceipts = [...(transaction.receiptImages ?? []), { url: nextUrl, kind: nextUrl.endsWith('.pdf') ? 'pdf' : 'image' }].slice(0, 5);
    await updateTransaction(accountId, id, { receiptImages: nextReceipts, transactionImages: nextReceipts });
    setReceiptUrl('');
    setLocalReceiptUri('');
  };

  const handleAddImage = async () => {
    if (!accountId || !id || !transaction) return;
    let nextUrl = imageUrl.trim();
    if (!nextUrl && localImageUri.trim()) {
      const result = await saveLocalMedia({
        localUri: localImageUri.trim(),
        mimeType: 'image/jpeg',
        ownerScope: `transaction:${id}`,
        persistCopy: false,
      });
      nextUrl = result.attachmentRef.url;
    }
    if (!nextUrl) return;
    const nextImages = [...(transaction.otherImages ?? []), { url: nextUrl, kind: 'image' }].slice(0, 5);
    await updateTransaction(accountId, id, { otherImages: nextImages });
    setImageUrl('');
    setLocalImageUri('');
  };

  const handleAddSelectedItems = useCallback(async () => {
    if (!accountId || !id || pickerSelectedIds.length === 0) return;
    const selectedItems = activePickerItems.filter((item) => pickerSelectedIds.includes(item.id));
    const conflicts = selectedItems.filter((item) => item.transactionId && item.transactionId !== id);
    const performAdd = async () => {
      await Promise.all(
        selectedItems.map((item) => {
          const update: Partial<Item> = { transactionId: id };
          if (!isCanonical && transaction?.budgetCategoryId) {
            update.inheritedBudgetCategoryId = transaction.budgetCategoryId;
          }
          if (scope === 'project' && projectId && item.projectId !== projectId) {
            update.projectId = projectId;
            update.spaceId = null;
          }
          if (scope === 'inventory' && item.projectId != null) {
            update.projectId = null;
            update.spaceId = null;
          }
          return updateItem(accountId, item.id, update);
        })
      );
      setPickerSelectedIds([]);
      setIsPickingItems(false);
    };
    if (conflicts.length > 0) {
      const names = conflicts
        .slice(0, 4)
        .map((item) => item.name?.trim() || item.description || 'Item');
      Alert.alert(
        'Reassign items?',
        `Some items are linked to another transaction. Reassign them?\n\n${names.join('\n')}`,
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Reassign', style: 'destructive', onPress: performAdd },
        ]
      );
      return;
    }
    await performAdd();
  }, [
    accountId,
    activePickerItems,
    id,
    isCanonical,
    pickerSelectedIds,
    projectId,
    scope,
    transaction?.budgetCategoryId,
  ]);

  const handleRemoveLinkedItem = async (itemId: string) => {
    if (!accountId) return;
    await updateItem(accountId, itemId, { transactionId: null });
  };

  const handleCreateItem = () => {
    router.push({
      pathname: '/items/new',
      params: {
        scope,
        projectId: projectId ?? '',
        transactionId: id ?? '',
        backTarget: fallbackTarget,
      },
    });
  };

  const handleDelete = () => {
    if (!accountId || !id) return;
    Alert.alert('Delete transaction', 'This will permanently delete this transaction.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteTransaction(accountId, id);
          router.replace(fallbackTarget);
        },
      },
    ]);
  };

  return (
    <Screen title="Transaction">
      <View style={styles.container}>
        <AppButton title="Back" variant="secondary" onPress={handleBack} />
        <AppText variant="title">Transaction detail</AppText>
        {isLoading ? (
          <AppText variant="body">Loading transaction…</AppText>
        ) : transaction ? (
          <>
            <View style={styles.actions}>
              <AppButton
                title={isEditing ? 'Cancel edit' : 'Edit'}
                variant="secondary"
                onPress={() => setIsEditing((prev) => !prev)}
                disabled={isCanonical}
              />
              <AppButton title="Delete" variant="secondary" onPress={handleDelete} />
            </View>
            {isEditing ? (
              <>
                <AppText variant="body">Source</AppText>
                <TextInput
                  value={source}
                  onChangeText={setSource}
                  placeholder="Source"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 })}
                />
                <AppText variant="body">Date</AppText>
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
                <AppText variant="body">Reimbursement</AppText>
                <TextInput
                  value={reimbursementType}
                  onChangeText={setReimbursementType}
                  placeholder="Reimbursement type"
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
                <AppText variant="body">Budget category id</AppText>
                <TextInput
                  value={budgetCategoryId}
                  onChangeText={setBudgetCategoryId}
                  placeholder="Budget category id"
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
                <View style={styles.actions}>
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
                <AppButton title="Save" onPress={handleSave} />
              </>
            ) : (
              <>
                <AppText variant="body">Source: {transaction.source ?? '—'}</AppText>
                <AppText variant="body">Date: {transaction.transactionDate ?? '—'}</AppText>
                <AppText variant="body">
                  Amount:{' '}
                  {typeof transaction.amountCents === 'number' ? `$${(transaction.amountCents / 100).toFixed(2)}` : '—'}
                </AppText>
                <AppText variant="body">Status: {transaction.status ?? '—'}</AppText>
                <AppText variant="body">Purchased by: {transaction.purchasedBy ?? '—'}</AppText>
                <AppText variant="body">Reimbursement: {transaction.reimbursementType ?? '—'}</AppText>
                <AppText variant="body">Notes: {transaction.notes?.trim() || '—'}</AppText>
              </>
            )}
            <AppText variant="caption">Scope: {scope ?? 'Unknown'}</AppText>
            {transaction.projectId ? <AppText variant="caption">Project: {transaction.projectId}</AppText> : null}
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
            <AppButton title="Add receipt" onPress={handleAddReceipt} />
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
            <AppButton title="Add image" onPress={handleAddImage} />
            <AppText variant="body">Itemization</AppText>
            {!itemizationEnabled && linkedItems.length > 0 ? (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                Itemization is off, but this transaction already has items.
              </AppText>
            ) : null}
            <View style={styles.actions}>
              <AppButton title="Create item" variant="secondary" onPress={handleCreateItem} disabled={isCanonical} />
              <AppButton
                title={isPickingItems ? 'Close picker' : 'Add existing items'}
                variant="secondary"
                onPress={() => {
                  setIsPickingItems((prev) => !prev);
                  setPickerSelectedIds([]);
                  setPickerTab('suggested');
                }}
                disabled={isCanonical}
              />
            </View>
            {isPickingItems ? (
              <View style={styles.pickerPanel}>
                <SegmentedControl
                  value={pickerTab}
                  options={pickerTabOptions}
                  onChange={(next) => {
                    setPickerTab(next);
                    setPickerSelectedIds([]);
                  }}
                  accessibilityLabel="Item picker tabs"
                />
                <TextInput
                  value={pickerQuery}
                  onChangeText={setPickerQuery}
                  placeholder="Search items"
                  placeholderTextColor={theme.colors.textSecondary}
                  style={getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 })}
                />
                <View style={styles.actions}>
                  <AppButton
                    title="Select all visible"
                    variant="secondary"
                    onPress={() =>
                      setPickerSelectedIds(
                        activePickerItems.filter((item) => item.transactionId !== id).map((item) => item.id)
                      )
                    }
                  />
                  <AppButton
                    title={`Add Selected (${pickerSelectedIds.length})`}
                    onPress={handleAddSelectedItems}
                    disabled={pickerSelectedIds.length === 0}
                  />
                </View>
                <View style={styles.list}>
                  {pickerGroups.map(([label, groupItems]) => {
                    const eligibleIds = groupItems.filter((item) => item.transactionId !== id).map((item) => item.id);
                    const groupAllSelected =
                      eligibleIds.length > 0 && eligibleIds.every((itemId) => pickerSelectedIds.includes(itemId));

                    if (groupItems.length > 1) {
                      return (
                        <GroupedItemCard
                          key={label}
                          summary={{ description: label }}
                          countLabel={`×${groupItems.length}`}
                          items={groupItems.map((item) => {
                            const description = item.name?.trim() || item.description || 'Item';
                            const locked = item.transactionId === id;
                            const conflict = !!item.transactionId && item.transactionId !== id;
                            const selected = pickerSelectedIds.includes(item.id);

                            return {
                              description,
                              selected,
                              onSelectedChange: locked
                                ? undefined
                                : (next) =>
                                    setPickerSelectedIds((prev) => {
                                      if (next) return prev.includes(item.id) ? prev : [...prev, item.id];
                                      return prev.filter((entry) => entry !== item.id);
                                    }),
                              onPress: locked
                                ? undefined
                                : () =>
                                    setPickerSelectedIds((prev) =>
                                      prev.includes(item.id)
                                        ? prev.filter((entry) => entry !== item.id)
                                        : [...prev, item.id]
                                    ),
                              statusLabel: locked ? 'Already linked' : conflict ? 'Linked elsewhere' : undefined,
                              style: locked ? { opacity: 0.6 } : undefined,
                            };
                          })}
                          selected={groupAllSelected}
                          onSelectedChange={
                            eligibleIds.length === 0
                              ? undefined
                              : (next) => {
                                  setPickerSelectedIds((prev) => {
                                    if (next) return Array.from(new Set([...prev, ...eligibleIds]));
                                    const remove = new Set(eligibleIds);
                                    return prev.filter((entry) => !remove.has(entry));
                                  });
                                }
                          }
                        />
                      );
                    }

                    const [only] = groupItems;
                    const description = only.name?.trim() || only.description || 'Item';
                    const locked = only.transactionId === id;
                    const conflict = !!only.transactionId && only.transactionId !== id;
                    const selected = pickerSelectedIds.includes(only.id);

                    return (
                      <ItemCard
                        key={only.id}
                        description={description}
                        selected={selected}
                        onSelectedChange={locked ? undefined : (next) => {
                          setPickerSelectedIds((prev) => {
                            if (next) return prev.includes(only.id) ? prev : [...prev, only.id];
                            return prev.filter((entry) => entry !== only.id);
                          });
                        }}
                        onPress={locked ? undefined : () => {
                          setPickerSelectedIds((prev) =>
                            prev.includes(only.id) ? prev.filter((entry) => entry !== only.id) : [...prev, only.id]
                          );
                        }}
                        statusLabel={locked ? 'Already linked' : conflict ? 'Linked elsewhere' : undefined}
                        style={locked ? { opacity: 0.6 } : undefined}
                      />
                    );
                  })}
                  {pickerGroups.length === 0 ? (
                    <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
                      No items available.
                    </AppText>
                  ) : null}
                  {pickerTab === 'outside' && outsideLoading ? (
                    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                      Loading outside items…
                    </AppText>
                  ) : null}
                  {pickerTab === 'outside' && outsideError ? (
                    <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                      {outsideError}
                    </AppText>
                  ) : null}
                </View>
              </View>
            ) : null}
            {linkedItems.length ? (
              <View style={styles.list}>
                {linkedItems.map((item) => (
                  <View key={item.id} style={styles.row}>
                    <AppText variant="body">{item.name?.trim() || item.description || 'Item'}</AppText>
                    <AppButton title="Remove" variant="secondary" onPress={() => handleRemoveLinkedItem(item.id)} />
                  </View>
                ))}
              </View>
            ) : (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                No items linked yet.
              </AppText>
            )}
            {error ? (
              <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
                {error}
              </AppText>
            ) : null}
          </>
        ) : (
          <AppText variant="body">Transaction not found.</AppText>
        )}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
  },
  actions: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
  },
  list: {
    gap: 8,
  },
  pickerPanel: {
    gap: 12,
  },
});
