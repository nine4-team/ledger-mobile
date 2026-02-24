import React, { useState, useEffect } from 'react';
import { ScrollView, View, StyleSheet } from 'react-native';

import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';
import { MultiSelectPicker } from '../MultiSelectPicker';
import { CategoryPickerList } from './CategoryPickerList';
import { VendorPicker } from '../VendorPicker';
import type { Transaction } from '../../data/transactionsService';

export type EditTransactionDetailsModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  transaction: Transaction;
  budgetCategories: Record<string, { name: string; metadata?: any }>;
  itemizationEnabled: boolean;
  onSave: (changes: Partial<Transaction>) => void;
  accountId: string;
};

function centsToDisplay(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '';
  return (cents / 100).toFixed(2);
}

function displayToCents(value: string): number | null {
  const trimmed = value.trim().replace(/[^0-9.]/g, '');
  if (!trimmed) return null;
  const parsed = parseFloat(trimmed);
  if (isNaN(parsed)) return null;
  return Math.round(parsed * 100);
}

const REIMBURSEMENT_OPTIONS = [
  { value: 'none' as const, label: 'None' },
  { value: 'owed-to-client' as const, label: 'Owed to Client' },
  { value: 'owed-to-company' as const, label: 'Owed to Business' },
];

const TYPE_OPTIONS = [
  { value: 'purchase' as const, label: 'Purchase' },
  { value: 'sale' as const, label: 'Sale' },
  { value: 'return' as const, label: 'Return' },
  { value: 'to-inventory' as const, label: 'To Inventory' },
];

const EMAIL_RECEIPT_OPTIONS = [
  { value: 'yes' as const, label: 'Yes' },
  { value: 'no' as const, label: 'No' },
];

export function EditTransactionDetailsModal({
  visible,
  onRequestClose,
  transaction,
  budgetCategories,
  itemizationEnabled,
  onSave,
  accountId,
}: EditTransactionDetailsModalProps) {
  const [source, setSource] = useState('');
  const [amount, setAmount] = useState('');
  const [transactionDate, setTransactionDate] = useState('');
  const [status, setStatus] = useState('');
  const [purchasedBy, setPurchasedBy] = useState('');
  const [reimbursementType, setReimbursementType] = useState('none');
  const [budgetCategoryId, setBudgetCategoryId] = useState('');
  const [transactionType, setTransactionType] = useState('purchase');
  const [hasEmailReceipt, setHasEmailReceipt] = useState('no');
  const [subtotal, setSubtotal] = useState('');
  const [taxRatePct, setTaxRatePct] = useState('');

  // Reset state from transaction props when modal becomes visible
  useEffect(() => {
    if (visible) {
      setSource(transaction.source ?? '');
      setAmount(centsToDisplay(transaction.amountCents));
      setTransactionDate(transaction.transactionDate ?? '');
      setStatus(transaction.status ?? '');
      setPurchasedBy(transaction.purchasedBy ?? '');
      setReimbursementType(transaction.reimbursementType || 'none');
      setBudgetCategoryId(transaction.budgetCategoryId ?? '');
      setTransactionType(transaction.transactionType || 'purchase');
      setHasEmailReceipt(transaction.hasEmailReceipt ? 'yes' : 'no');
      setSubtotal(centsToDisplay(transaction.subtotalCents));
      setTaxRatePct(
        typeof transaction.taxRatePct === 'number'
          ? transaction.taxRatePct.toFixed(2)
          : ''
      );
    }
  }, [visible]);

  const handleSave = () => {
    const changes: Record<string, unknown> = {
      source: source.trim() || null,
      amountCents: displayToCents(amount),
      transactionDate: transactionDate.trim() || null,
      status: status.trim() || null,
      purchasedBy: purchasedBy.trim() || null,
      reimbursementType: reimbursementType === 'none' ? null : reimbursementType,
      budgetCategoryId: budgetCategoryId || null,
      transactionType: transactionType || null,
      hasEmailReceipt: hasEmailReceipt === 'yes',
    };

    if (itemizationEnabled) {
      changes.subtotalCents = displayToCents(subtotal);
      const parsedTaxRate = parseFloat(taxRatePct.trim());
      changes.taxRatePct = isNaN(parsedTaxRate) ? null : parsedTaxRate;
    }

    onSave(changes as Partial<Transaction>);
  };

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title="Edit Transaction Details"
      primaryAction={{
        title: 'Save',
        onPress: handleSave,
      }}
      containerStyle={{ maxHeight: '90%' }}
    >
      <ScrollView
        showsVerticalScrollIndicator={false}
        style={styles.scroll}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.fields}>
          <VendorPicker
            accountId={accountId}
            value={source}
            onChangeValue={setSource}
          />
          <FormField
            label="Amount"
            value={amount}
            onChangeText={setAmount}
            placeholder="$0.00"
            inputProps={{ keyboardType: 'decimal-pad' }}
          />
          <FormField
            label="Date"
            value={transactionDate}
            onChangeText={setTransactionDate}
            placeholder="YYYY-MM-DD"
          />
          <FormField
            label="Status"
            value={status}
            onChangeText={setStatus}
            placeholder="e.g. needs_review, complete"
          />
          <FormField
            label="Purchased By"
            value={purchasedBy}
            onChangeText={setPurchasedBy}
            placeholder="Who made this purchase?"
          />
          <MultiSelectPicker
            label="Transaction Type"
            value={transactionType}
            onChange={(val) => setTransactionType(val as string)}
            options={TYPE_OPTIONS}
          />
          <MultiSelectPicker
            label="Reimbursement Type"
            value={reimbursementType}
            onChange={(val) => setReimbursementType(val as string)}
            options={REIMBURSEMENT_OPTIONS}
          />
          <CategoryPickerList
            categories={budgetCategories}
            selectedId={budgetCategoryId || null}
            onSelect={setBudgetCategoryId}
            maxHeight={160}
          />
          <MultiSelectPicker
            label="Email Receipt"
            value={hasEmailReceipt}
            onChange={(val) => setHasEmailReceipt(val as string)}
            options={EMAIL_RECEIPT_OPTIONS}
          />
          {itemizationEnabled && (
            <>
              <FormField
                label="Subtotal"
                value={subtotal}
                onChangeText={setSubtotal}
                placeholder="$0.00"
                inputProps={{ keyboardType: 'decimal-pad' }}
              />
              <FormField
                label="Tax Rate (%)"
                value={taxRatePct}
                onChangeText={setTaxRatePct}
                placeholder="e.g. 8.25"
                inputProps={{ keyboardType: 'decimal-pad' }}
              />
            </>
          )}
        </View>
      </ScrollView>
    </FormBottomSheet>
  );
}

const styles = StyleSheet.create({
  scroll: {
    maxHeight: 450,
  },
  fields: {
    gap: 16,
  },
});
