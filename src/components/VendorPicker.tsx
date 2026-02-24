import React, { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { AppText } from './AppText';
import { FormField } from './FormField';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextSecondaryStyle } from '../ui/styles/typography';
import { getTextInputStyle } from '../ui/styles/forms';
import { subscribeToVendorDefaults } from '../data/vendorDefaultsService';

export interface VendorPickerProps {
  accountId: string;
  value: string;
  onChangeValue: (source: string) => void;
  maxHeight?: number;
}

export function VendorPicker({ accountId, value, onChangeValue, maxHeight = 200 }: VendorPickerProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [allSlots, setAllSlots] = useState<string[]>([]);
  useEffect(() => {
    if (!accountId) {
      setAllSlots([]);
      return;
    }
    return subscribeToVendorDefaults(accountId, setAllSlots);
  }, [accountId]);

  const vendors = useMemo(
    () => Array.from(new Set(allSlots.filter((v) => v.trim() !== ''))),
    [allSlots],
  );

  const [otherMode, setOtherMode] = useState(false);

  // Derive initial other mode when vendors load (or on edit modal open)
  useEffect(() => {
    if (vendors.length === 0) return;
    if (value && !vendors.includes(value)) {
      setOtherMode(true);
    }
  }, [vendors]); // eslint-disable-line react-hooks/exhaustive-deps

  const inputStyle = useMemo(
    () => getTextInputStyle(uiKitTheme, { radius: 10, paddingVertical: 10, paddingHorizontal: 12 }),
    [uiKitTheme],
  );

  const handleSelectVendor = (vendor: string) => {
    setOtherMode(false);
    onChangeValue(vendor);
  };

  const handleSelectOther = () => {
    setOtherMode(true);
    onChangeValue('');
  };

  // Fallback: no vendors configured → plain text input
  if (vendors.length === 0) {
    return (
      <FormField
        label="Source"
        value={value}
        onChangeText={onChangeValue}
        placeholder="e.g. Home Depot, Amazon"
      />
    );
  }

  return (
    <View style={styles.container}>
      <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
        Source (scroll)
      </AppText>
      <View style={[styles.borderLine, { borderColor: uiKitTheme.border.secondary }]} />
      <ScrollView style={{ maxHeight }} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator>
        <View style={styles.list}>
          {vendors.map((vendor) => {
            const isSelected = !otherMode && value === vendor;
            return (
              <Pressable
                key={vendor}
                onPress={() => handleSelectVendor(vendor)}
                style={[
                  styles.option,
                  {
                    borderColor: isSelected
                      ? theme.colors.primary
                      : uiKitTheme.border.secondary,
                    backgroundColor: isSelected
                      ? uiKitTheme.background.surface
                      : 'transparent',
                  },
                ]}
              >
                <View
                  style={[
                    styles.radio,
                    {
                      borderColor: isSelected
                        ? theme.colors.primary
                        : uiKitTheme.border.secondary,
                    },
                  ]}
                >
                  {isSelected && (
                    <View
                      style={[
                        styles.radioFill,
                        { backgroundColor: theme.colors.primary },
                      ]}
                    />
                  )}
                </View>
                <AppText variant="body">{vendor}</AppText>
              </Pressable>
            );
          })}
          <Pressable
            onPress={handleSelectOther}
            style={[
              styles.option,
              {
                borderColor: otherMode
                  ? theme.colors.primary
                  : uiKitTheme.border.secondary,
                backgroundColor: otherMode
                  ? uiKitTheme.background.surface
                  : 'transparent',
              },
            ]}
          >
            <View
              style={[
                styles.radio,
                {
                  borderColor: otherMode
                    ? theme.colors.primary
                    : uiKitTheme.border.secondary,
                },
              ]}
            >
              {otherMode && (
                <View
                  style={[
                    styles.radioFill,
                    { backgroundColor: theme.colors.primary },
                  ]}
                />
              )}
            </View>
            <AppText variant="body">Other</AppText>
          </Pressable>
        </View>
      </ScrollView>
      <View style={[styles.borderLine, { borderColor: uiKitTheme.border.secondary }]} />
      {otherMode && (
        <TextInput
          value={value}
          onChangeText={onChangeValue}
          placeholder="e.g. Home Depot, Amazon"
          style={inputStyle}
          placeholderTextColor={uiKitTheme.input.placeholder}
          autoCorrect={false}
          autoFocus
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 6,
  },
  borderLine: {
    borderBottomWidth: 1,
  },
  scrollContent: {
    paddingRight: 8,
  },
  list: {
    gap: 6,
    paddingVertical: 6,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 10,
    borderWidth: 1,
    gap: 12,
  },
  radio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  radioFill: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
});
