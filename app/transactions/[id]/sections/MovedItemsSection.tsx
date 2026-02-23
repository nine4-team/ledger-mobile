import React from 'react';
import { View, StyleSheet } from 'react-native';
import { ItemCard } from '../../../../src/components/ItemCard';
import type { ScopedItem } from '../../../../src/data/scopedListData';
import type { AttachmentRef } from '../../../../src/offline/media';
import { resolveAttachmentUri } from '../../../../src/offline/media';

interface MovedItemsSectionProps {
  items: ScopedItem[];
}

function formatCents(value?: number | null): string | undefined {
  if (typeof value !== 'number') return undefined;
  return `$${(value / 100).toFixed(2)}`;
}

function getDisplayPriceCents(item: ScopedItem): number | null {
  if (typeof item.projectPriceCents === 'number' && typeof item.purchasePriceCents === 'number' && item.projectPriceCents !== item.purchasePriceCents) {
    return item.projectPriceCents;
  }
  if (typeof item.purchasePriceCents === 'number') return item.purchasePriceCents;
  if (typeof item.projectPriceCents === 'number') return item.projectPriceCents;
  return null;
}

function getPrimaryImageUri(images?: AttachmentRef[] | null): string | undefined {
  const list = images ?? [];
  const primary = list.find((img) => img.isPrimary) ?? list[0];
  if (!primary) return undefined;
  return resolveAttachmentUri(primary) ?? primary.url ?? undefined;
}

export function MovedItemsSection({ items }: MovedItemsSectionProps) {
  if (items.length === 0) return null;

  return (
    <View style={styles.container}>
      {items.map((item) => (
        <ItemCard
          key={item.id}
          name={item.name ?? ''}
          sku={item.sku ?? undefined}
          sourceLabel={item.source ?? undefined}
          priceLabel={formatCents(getDisplayPriceCents(item))}
          thumbnailUri={getPrimaryImageUri(item.images)}
        />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    opacity: 0.5,
    gap: 10,
  },
});
