import { useState, useEffect } from 'react';

import { FormBottomSheet } from '../FormBottomSheet';
import { FormField } from '../FormField';

export type EditItemDetailsModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  item: {
    name?: string | null;
    source?: string | null;
    sku?: string | null;
    purchasePriceCents?: number | null;
    projectPriceCents?: number | null;
    marketValueCents?: number | null;
  };
  onSave: (changes: Record<string, unknown>) => void;
};

function centsToDisplay(cents: number | null | undefined): string {
  if (typeof cents !== 'number') return '';
  return (cents / 100).toFixed(2);
}

function displayToCents(value: string): number | null {
  const trimmed = value.trim().replace(/^\$/, '');
  if (!trimmed) return null;
  const parsed = parseFloat(trimmed);
  if (isNaN(parsed)) return null;
  return Math.round(parsed * 100);
}

export function EditItemDetailsModal({
  visible,
  onRequestClose,
  item,
  onSave,
}: EditItemDetailsModalProps) {
  const [name, setName] = useState('');
  const [source, setSource] = useState('');
  const [sku, setSku] = useState('');
  const [purchasePrice, setPurchasePrice] = useState('');
  const [projectPrice, setProjectPrice] = useState('');
  const [marketValue, setMarketValue] = useState('');

  // Reset state from item props when modal becomes visible
  useEffect(() => {
    if (visible) {
      setName(item.name ?? '');
      setSource(item.source ?? '');
      setSku(item.sku ?? '');
      setPurchasePrice(centsToDisplay(item.purchasePriceCents));
      setProjectPrice(centsToDisplay(item.projectPriceCents));
      setMarketValue(centsToDisplay(item.marketValueCents));
    }
  }, [visible]);

  const handleSave = () => {
    const changes: Record<string, unknown> = {
      name: name.trim() || null,
      source: source.trim() || null,
      sku: sku.trim() || null,
      purchasePriceCents: displayToCents(purchasePrice),
      projectPriceCents: displayToCents(projectPrice),
      marketValueCents: displayToCents(marketValue),
    };
    onSave(changes);
  };

  return (
    <FormBottomSheet
      visible={visible}
      onRequestClose={onRequestClose}
      title="Edit Item Details"
      primaryAction={{
        title: 'Save',
        onPress: handleSave,
      }}
    >
      <FormField
        label="Name"
        value={name}
        onChangeText={setName}
        placeholder="Item name"
      />
      <FormField
        label="Source"
        value={source}
        onChangeText={setSource}
        placeholder="e.g. Home Depot"
      />
      <FormField
        label="SKU"
        value={sku}
        onChangeText={setSku}
        placeholder="e.g. ABC-123"
      />
      <FormField
        label="Purchase Price"
        value={purchasePrice}
        onChangeText={setPurchasePrice}
        placeholder="$0.00"
        inputProps={{ keyboardType: 'decimal-pad' }}
      />
      <FormField
        label="Project Price"
        value={projectPrice}
        onChangeText={setProjectPrice}
        placeholder="$0.00"
        inputProps={{ keyboardType: 'decimal-pad' }}
      />
      <FormField
        label="Market Value"
        value={marketValue}
        onChangeText={setMarketValue}
        placeholder="$0.00"
        inputProps={{ keyboardType: 'decimal-pad' }}
      />
    </FormBottomSheet>
  );
}
