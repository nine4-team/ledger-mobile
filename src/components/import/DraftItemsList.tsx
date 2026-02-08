import React, { useCallback } from 'react';
import {
  FlatList,
  Image,
  StyleSheet,
  Switch,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { AppText } from '../AppText';
import { useTheme } from '../../theme/ThemeProvider';

export type DraftLineItem = {
  description: string;
  qty: number;
  unitPrice: string;
  total: string;
  sku?: string;
  thumbnailDataUri?: string;
  attributeLines?: string[];
  isIncluded: boolean;
};

type DraftItemsListProps = {
  items: DraftLineItem[];
  onItemChange: (index: number, updates: Partial<DraftLineItem>) => void;
  onItemRemove: (index: number) => void;
  vendor: 'amazon' | 'wayfair';
};

export function DraftItemsList({ items, onItemChange, onItemRemove, vendor }: DraftItemsListProps) {
  const theme = useTheme();

  const renderItem = useCallback(
    ({ item, index }: { item: DraftLineItem; index: number }) => (
      <DraftItemRow
        item={item}
        index={index}
        vendor={vendor}
        onItemChange={onItemChange}
        onItemRemove={onItemRemove}
        theme={theme}
      />
    ),
    [onItemChange, onItemRemove, theme, vendor],
  );

  const keyExtractor = useCallback((_item: DraftLineItem, index: number) => `draft-${index}`, []);

  if (items.length === 0) {
    return (
      <View style={styles.emptyContainer}>
        <AppText variant="caption">No items parsed from invoice.</AppText>
      </View>
    );
  }

  return (
    <FlatList
      data={items}
      renderItem={renderItem}
      keyExtractor={keyExtractor}
      scrollEnabled={false}
      ItemSeparatorComponent={() => (
        <View style={[styles.separator, { backgroundColor: theme.colors.border }]} />
      )}
    />
  );
}

type DraftItemRowProps = {
  item: DraftLineItem;
  index: number;
  vendor: 'amazon' | 'wayfair';
  onItemChange: (index: number, updates: Partial<DraftLineItem>) => void;
  onItemRemove: (index: number) => void;
  theme: ReturnType<typeof useTheme>;
};

function DraftItemRow({ item, index, vendor, onItemChange, onItemRemove, theme }: DraftItemRowProps) {
  return (
    <View style={[styles.itemRow, !item.isIncluded && styles.itemRowExcluded]}>
      <View style={styles.itemHeader}>
        <Switch
          value={item.isIncluded}
          onValueChange={(value) => onItemChange(index, { isIncluded: value })}
          trackColor={{ false: theme.colors.border, true: theme.colors.primary }}
        />
        <View style={styles.itemHeaderText}>
          <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
            Item {index + 1}
          </AppText>
          <TouchableOpacity onPress={() => onItemRemove(index)} activeOpacity={0.7}>
            <AppText variant="caption" style={{ color: theme.colors.error }}>
              Remove
            </AppText>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.itemBody}>
        {vendor === 'wayfair' && item.thumbnailDataUri ? (
          <Image
            source={{ uri: item.thumbnailDataUri }}
            style={styles.thumbnail}
            resizeMode="cover"
          />
        ) : null}

        <View style={styles.itemFields}>
          <AppText variant="caption">Description</AppText>
          <TextInput
            style={[
              styles.textInput,
              {
                color: theme.colors.text,
                borderColor: theme.colors.border,
                backgroundColor: theme.colors.background,
              },
            ]}
            value={item.description}
            onChangeText={(text) => onItemChange(index, { description: text })}
            placeholder="Item description"
            placeholderTextColor={theme.colors.textSecondary}
            multiline
          />

          <View style={styles.qtyPriceRow}>
            <View style={styles.qtyField}>
              <AppText variant="caption">Qty</AppText>
              <TextInput
                style={[
                  styles.textInput,
                  styles.numberInput,
                  {
                    color: theme.colors.text,
                    borderColor: theme.colors.border,
                    backgroundColor: theme.colors.background,
                  },
                ]}
                value={String(item.qty)}
                onChangeText={(text) => {
                  const qty = parseInt(text, 10);
                  if (!isNaN(qty) && qty > 0) {
                    onItemChange(index, { qty });
                  }
                }}
                keyboardType="number-pad"
                placeholder="1"
                placeholderTextColor={theme.colors.textSecondary}
              />
            </View>

            <View style={styles.priceField}>
              <AppText variant="caption">Unit Price</AppText>
              <TextInput
                style={[
                  styles.textInput,
                  styles.numberInput,
                  {
                    color: theme.colors.text,
                    borderColor: theme.colors.border,
                    backgroundColor: theme.colors.background,
                  },
                ]}
                value={item.unitPrice}
                onChangeText={(text) => onItemChange(index, { unitPrice: text })}
                keyboardType="decimal-pad"
                placeholder="0.00"
                placeholderTextColor={theme.colors.textSecondary}
              />
            </View>

            <View style={styles.totalField}>
              <AppText variant="caption">Total</AppText>
              <AppText variant="body" style={styles.totalText}>
                ${item.total}
              </AppText>
            </View>
          </View>

          {vendor === 'wayfair' && item.sku ? (
            <AppText variant="caption" style={{ color: theme.colors.textSecondary }}>
              SKU: {item.sku}
            </AppText>
          ) : null}

          {vendor === 'wayfair' && item.attributeLines && item.attributeLines.length > 0 ? (
            <View style={styles.attributesList}>
              {item.attributeLines.map((line, attrIdx) => (
                <AppText key={attrIdx} variant="caption" style={{ color: theme.colors.textSecondary }}>
                  {line}
                </AppText>
              ))}
            </View>
          ) : null}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  emptyContainer: {
    padding: 16,
    alignItems: 'center',
  },
  separator: {
    height: 1,
    marginVertical: 4,
  },
  itemRow: {
    paddingVertical: 8,
    gap: 8,
  },
  itemRowExcluded: {
    opacity: 0.5,
  },
  itemHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  itemHeaderText: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  itemBody: {
    flexDirection: 'row',
    gap: 10,
  },
  thumbnail: {
    width: 48,
    height: 48,
    borderRadius: 6,
  },
  itemFields: {
    flex: 1,
    gap: 4,
  },
  textInput: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
    fontSize: 14,
  },
  qtyPriceRow: {
    flexDirection: 'row',
    gap: 8,
    alignItems: 'flex-start',
  },
  qtyField: {
    width: 60,
    gap: 2,
  },
  priceField: {
    flex: 1,
    gap: 2,
  },
  totalField: {
    flex: 1,
    gap: 2,
  },
  totalText: {
    paddingVertical: 6,
    fontWeight: '600',
  },
  numberInput: {
    textAlign: 'right',
  },
  attributesList: {
    marginTop: 2,
    gap: 1,
  },
});
