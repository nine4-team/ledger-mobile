import React, { useEffect, useMemo, useState } from 'react';
import { FlatList, Pressable, StyleSheet, TextInput, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

import { AppText } from '../AppText';
import { BottomSheet } from '../BottomSheet';
import { useTheme } from '../../theme/ThemeProvider';
import { useUIKitTheme } from '../../theme/ThemeProvider';
import { getTextInputStyle } from '../../ui/styles/forms';
import { ScopeConfig } from '../../data/scopeConfig';
import {
  ScopedTransaction,
  subscribeToScopedTransactions,
} from '../../data/scopedListData';

export interface ReturnTransactionPickerModalProps {
  visible: boolean;
  onRequestClose: () => void;
  accountId: string;
  scopeConfig: ScopeConfig;
  /** Called with the selected return transaction */
  onConfirm: (transaction: ScopedTransaction) => void;
  /** Called when user wants to create a new return transaction */
  onCreateNew: () => void;
  /** Optional subtitle like "Moving 1 item" */
  subtitle?: string;
}

function formatCents(value?: number | null): string {
  if (typeof value !== 'number') return 'No amount';
  return `$${(value / 100).toFixed(2)}`;
}

function formatDate(dateStr?: string | null): string {
  if (!dateStr) return '';
  try {
    const d = new Date(dateStr);
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return dateStr;
  }
}

export function ReturnTransactionPickerModal({
  visible,
  onRequestClose,
  accountId,
  scopeConfig,
  onConfirm,
  onCreateNew,
  subtitle,
}: ReturnTransactionPickerModalProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [transactions, setTransactions] = useState<ScopedTransaction[]>([]);
  const [search, setSearch] = useState('');

  useEffect(() => {
    if (!visible || !accountId) return;
    const unsub = subscribeToScopedTransactions(accountId, scopeConfig, setTransactions);
    return unsub;
  }, [visible, accountId, scopeConfig]);

  // Reset search when closed
  useEffect(() => {
    if (!visible) setSearch('');
  }, [visible]);

  // Filter to return transactions only, then sort and search
  const filtered = useMemo(() => {
    const returnTxns = transactions.filter(
      (t) => (t.transactionType ?? '').trim().toLowerCase() === 'return',
    );

    const sorted = [...returnTxns].sort((a, b) => {
      const da = a.transactionDate ?? '';
      const db = b.transactionDate ?? '';
      return db.localeCompare(da);
    });

    if (!search.trim()) return sorted;
    const q = search.trim().toLowerCase();
    return sorted.filter((t) => {
      const source = (t.source ?? '').toLowerCase();
      const notes = (t.notes ?? '').toLowerCase();
      const amount = formatCents(t.amountCents).toLowerCase();
      return source.includes(q) || notes.includes(q) || amount.includes(q);
    });
  }, [transactions, search]);

  const inputStyle = useMemo(
    () => getTextInputStyle(uiKitTheme, { padding: 10, fontSize: 14 }),
    [uiKitTheme],
  );

  const handleSelect = (transaction: ScopedTransaction) => {
    onConfirm(transaction);
    onRequestClose();
  };

  const renderItem = ({ item }: { item: ScopedTransaction }) => {
    const source = item.source?.trim() || 'Untitled';
    const date = formatDate(item.transactionDate);
    const amount = formatCents(item.amountCents);

    return (
      <Pressable
        style={({ pressed }) => [
          styles.row,
          { borderBottomColor: theme.colors.border },
          pressed && { opacity: 0.6 },
        ]}
        onPress={() => handleSelect(item)}
      >
        <View style={styles.rowLeft}>
          <AppText variant="body" numberOfLines={1}>{source}</AppText>
          {date ? (
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              {date}
            </AppText>
          ) : null}
        </View>
        <AppText variant="body" style={{ color: theme.colors.textSecondary }}>
          {amount}
        </AppText>
      </Pressable>
    );
  };

  return (
    <BottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      containerStyle={styles.sheet}
    >
      <View style={styles.header}>
        <AppText variant="body" style={styles.title}>Move to Return Transaction</AppText>
        {subtitle ? (
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            {subtitle}
          </AppText>
        ) : null}
      </View>
      <View style={styles.content}>
        <Pressable
          style={({ pressed }) => [
            styles.createRow,
            { borderBottomColor: theme.colors.border },
            pressed && { opacity: 0.6 },
          ]}
          onPress={() => {
            onCreateNew();
            onRequestClose();
          }}
        >
          <MaterialIcons name="add" size={20} color={theme.colors.primary} />
          <AppText variant="body" style={{ color: theme.colors.primary }}>
            Create New Return Transaction
          </AppText>
        </Pressable>
        <TextInput
          style={inputStyle}
          value={search}
          onChangeText={setSearch}
          placeholder="Search return transactions..."
          placeholderTextColor={theme.colors.inputPlaceholder ?? theme.colors.textSecondary}
          autoCapitalize="none"
          autoCorrect={false}
        />
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={renderItem}
          style={styles.list}
          keyboardShouldPersistTaps="handled"
          ListEmptyComponent={
            <AppText
              variant="caption"
              style={{ color: theme.colors.textSecondary, textAlign: 'center', paddingVertical: 24 }}
            >
              {transactions.length === 0
                ? 'No return transactions in this project. Create one above.'
                : 'No matches.'}
            </AppText>
          }
        />
      </View>
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  sheet: {
    height: '75%',
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 12,
    gap: 4,
  },
  title: {
    fontWeight: '700',
  },
  content: {
    flex: 1,
    paddingHorizontal: 16,
    paddingBottom: 8,
    gap: 12,
  },
  list: {
    flex: 1,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
    paddingHorizontal: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 12,
  },
  rowLeft: {
    flex: 1,
    gap: 2,
  },
  createRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 8,
  },
});
