import React, { useMemo, useState } from 'react';
import { Pressable, RefreshControl, StyleSheet, View } from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

import { AppScrollView } from '../components/AppScrollView';
import { AppText } from '../components/AppText';
import { AppButton } from '../components/AppButton';
import { BottomSheet } from '../components/BottomSheet';
import { InfoCard } from '../components/InfoCard';
import { FormModal } from '../components/FormModal';
import { FormField } from '../components/FormField';
import { ScreenTabItem, ScreenTabs } from '../components/ScreenTabs';
import { SegmentedControl } from '../components/SegmentedControl';
import { SelectorCircle } from '../components/SelectorCircle';
import { MultiSelectPicker } from '../components/MultiSelectPicker';
import { useScreenRefresh } from '../components/Screen';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { layout } from '../ui/styles/layout';
import { getCardStyle, surface } from '../ui/styles/surfaces';
import { getTextSecondaryStyle, textEmphasis } from '../ui/styles/typography';

const PREVIEW_TABS: ScreenTabItem[] = [
  { key: 'tab_one', label: 'Tab One', accessibilityLabel: 'Preview tab one' },
  { key: 'tab_two', label: 'Tab Two', accessibilityLabel: 'Preview tab two' },
  { key: 'tab_three', label: 'Tab Three', accessibilityLabel: 'Preview tab three' },
];

export function ComponentsGallery() {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const screenRefresh = useScreenRefresh();

  const refreshControl = screenRefresh ? (
    <RefreshControl refreshing={screenRefresh.refreshing} onRefresh={screenRefresh.onRefresh} />
  ) : undefined;

  const [segmentedValue, setSegmentedValue] = useState<'left' | 'middle' | 'right'>('left');
  const [tabsValue, setTabsValue] = useState(PREVIEW_TABS[0]?.key ?? 'tab_one');
  const [pickerValue, setPickerValue] = useState<'standard' | 'itemized' | 'fee'>('standard');
  const [multiPickerValue, setMultiPickerValue] = useState<string[]>([]);
  const [sheetVisible, setSheetVisible] = useState(false);
  const [draftName, setDraftName] = useState('Ada Lovelace');
  const [formModalVisible, setFormModalVisible] = useState(false);
  const [formName, setFormName] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const tabsBorderStyle = useMemo(() => ({ borderColor: uiKitTheme.border.primary }), [uiKitTheme]);
  const sheetTitleDividerStyle = useMemo(
    () => ({ borderBottomColor: uiKitTheme.border.secondary }),
    [uiKitTheme]
  );

  const cardStyle = useMemo(
    () => [surface.overflowHidden, getCardStyle(uiKitTheme, { radius: 12, padding: theme.spacing.lg })],
    [theme.spacing.lg, uiKitTheme]
  );

  return (
    <AppScrollView style={styles.scroll} contentContainerStyle={styles.scrollContent} refreshControl={refreshControl}>
      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Typography
        </AppText>
        <View style={cardStyle}>
          <AppText variant="h1">Heading 1</AppText>
          <AppText variant="h2">Heading 2</AppText>
          <AppText variant="body">Body text example for multi-line layouts and density checks.</AppText>
          <AppText variant="caption">Caption / secondary text</AppText>
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Buttons
        </AppText>
        <View style={cardStyle}>
          <View style={styles.row}>
            <View style={styles.flex}>
              <AppButton title="Primary" onPress={() => {}} />
            </View>
            <View style={styles.flex}>
              <AppButton title="Secondary" variant="secondary" onPress={() => {}} />
            </View>
          </View>
          <View style={styles.row}>
            <View style={styles.flex}>
              <AppButton title="Loading" loading onPress={() => {}} />
            </View>
            <View style={styles.flex}>
              <AppButton title="Disabled" disabled onPress={() => {}} />
            </View>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Controls
        </AppText>
        <View style={cardStyle}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            SegmentedControl
          </AppText>
          <SegmentedControl
            accessibilityLabel="Components gallery segmented control"
            value={segmentedValue}
            onChange={setSegmentedValue}
            options={[
              {
                value: 'left',
                label: 'Left',
                icon: (
                  <MaterialIcons
                    name="format-align-left"
                    size={18}
                    color={segmentedValue === 'left' ? uiKitTheme.text.primary : uiKitTheme.text.secondary}
                  />
                ),
              },
              {
                value: 'middle',
                label: 'Mid',
                icon: (
                  <MaterialIcons
                    name="format-align-center"
                    size={18}
                    color={segmentedValue === 'middle' ? uiKitTheme.text.primary : uiKitTheme.text.secondary}
                  />
                ),
              },
              {
                value: 'right',
                label: 'Right',
                icon: (
                  <MaterialIcons
                    name="format-align-right"
                    size={18}
                    color={segmentedValue === 'right' ? uiKitTheme.text.primary : uiKitTheme.text.secondary}
                  />
                ),
              },
            ]}
          />

          <View style={styles.divider} />

          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            SelectorCircle
          </AppText>
          <View style={[layout.row, styles.selectorRow]}>
            <View style={styles.selectorItem}>
              <SelectorCircle selected={false} />
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                Off
              </AppText>
            </View>
            <View style={styles.selectorItem}>
              <SelectorCircle selected indicator="dot" />
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                Dot
              </AppText>
            </View>
            <View style={styles.selectorItem}>
              <SelectorCircle selected indicator="check" />
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
                Check
              </AppText>
            </View>
          </View>

          <View style={styles.divider} />

          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            MultiSelectPicker (Single-select)
          </AppText>
          <MultiSelectPicker
            value={pickerValue}
            onChange={(value) => setPickerValue(value as 'standard' | 'itemized' | 'fee')}
            options={[
              {
                value: 'standard',
                label: 'Standard',
                description: 'Regular budget category for tracking expenses',
              },
              {
                value: 'itemized',
                label: 'Itemized',
                description: 'Category for tracking individual items',
              },
              {
                value: 'fee',
                label: 'Fee',
                description: 'Category for tracking fees and revenue',
              },
            ]}
            helperText="Select a single category type"
          />

          <View style={styles.divider} />

          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            MultiSelectPicker (Multi-select)
          </AppText>
          <MultiSelectPicker
            value={multiPickerValue}
            onChange={(value) => setMultiPickerValue(value as string[])}
            multiSelect
            options={[
              {
                value: 'option1',
                label: 'Option 1',
                description: 'First option description',
              },
              {
                value: 'option2',
                label: 'Option 2',
                description: 'Second option description',
              },
              {
                value: 'option3',
                label: 'Option 3',
                description: 'Third option description',
              },
            ]}
            helperText="Select multiple options"
          />
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Tabs
        </AppText>
        <View style={[surface.overflowHidden, styles.tabsContainer, tabsBorderStyle]}>
          <ScreenTabs
            tabs={PREVIEW_TABS}
            value={tabsValue}
            onChange={setTabsValue}
            containerStyle={styles.tabsStrip}
          />
          <View style={[cardStyle, styles.cardNoRadius]}>
            <AppText variant="body">Selected: {PREVIEW_TABS.find((t) => t.key === tabsValue)?.label ?? tabsValue}</AppText>
            <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
              This is a lightweight preview of the `ScreenTabs` style.
            </AppText>
          </View>
        </View>
      </View>

      <View style={styles.section}>
        <InfoCard
          title="InfoCard"
          description="A card surface with consistent spacing, text styles, and actions."
          footer={
            <InfoCard.Actions
              secondary={{ title: 'Secondary', variant: 'secondary', onPress: () => {} }}
              primary={{ title: 'Primary', onPress: () => {} }}
            />
          }
        >
          <InfoCard.Field label="Label" value="Value" />
          <InfoCard.EditableField label="Editable" value={draftName} onChangeText={setDraftName} />
        </InfoCard>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          Forms
        </AppText>
        <View style={cardStyle}>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            FormField
          </AppText>
          <FormField
            label="Example Field"
            value={draftName}
            onChangeText={setDraftName}
            placeholder="Enter text"
            helperText="This is helper text"
          />
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          BottomSheet
        </AppText>
        <View style={cardStyle}>
          <AppButton title="Open Bottom Sheet" onPress={() => setSheetVisible(true)} />
        </View>
      </View>

      <View style={styles.section}>
        <AppText
          variant="caption"
          style={[styles.sectionTitle, textEmphasis.sectionLabel, getTextSecondaryStyle(uiKitTheme)]}
        >
          FormModal
        </AppText>
        <View style={cardStyle}>
          <AppButton title="Open Form Modal" onPress={() => setFormModalVisible(true)} />
        </View>
      </View>

      <BottomSheet visible={sheetVisible} onRequestClose={() => setSheetVisible(false)}>
        <View style={[styles.sheetTitleRow, sheetTitleDividerStyle]}>
          <AppText variant="body" style={[styles.sheetTitle, textEmphasis.strong]}>
            Bottom sheet
          </AppText>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Close bottom sheet"
            hitSlop={10}
            onPress={() => setSheetVisible(false)}
            style={({ pressed }) => [styles.sheetCloseButton, pressed && styles.pressed]}
          >
            <MaterialIcons name="close" size={22} color={theme.colors.textSecondary} />
          </Pressable>
        </View>
        <View style={styles.sheetContent}>
          <AppText variant="body">Use this area to preview sheet layout, padding, and typography.</AppText>
          <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>
            Tap outside the sheet to close.
          </AppText>
          <AppButton title="Close" variant="secondary" onPress={() => setSheetVisible(false)} />
        </View>
      </BottomSheet>

      <FormModal
        visible={formModalVisible}
        onRequestClose={() => {
          setFormModalVisible(false);
          setFormName('');
          setFormDescription('');
        }}
        title="Create New Item"
        description="Use this modal to create simple objects like budget categories, spaces, etc."
        primaryAction={{
          title: 'Create',
          onPress: () => {
            // Simulate save
            setTimeout(() => {
              setFormModalVisible(false);
              setFormName('');
              setFormDescription('');
            }, 500);
          },
          disabled: !formName.trim(),
        }}
      >
        <FormField
          label="Name"
          value={formName}
          onChangeText={setFormName}
          placeholder="Enter name"
          helperText="This is a required field"
        />
        <FormField
          label="Description"
          value={formDescription}
          onChangeText={setFormDescription}
          placeholder="Optional description"
        />
      </FormModal>
    </AppScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  scrollContent: {
    paddingTop: 0,
  },
  section: {
    marginBottom: 18,
  },
  sectionTitle: {
    marginBottom: 8,
  },
  row: {
    flexDirection: 'row',
    gap: 10,
  },
  flex: {
    flex: 1,
  },
  divider: {
    height: 1,
    backgroundColor: '#E6E6E6',
    marginVertical: 14,
  },
  selectorRow: {
    gap: 14,
    marginTop: 6,
  },
  selectorItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  tabsContainer: {
    borderRadius: 12,
    borderWidth: 1,
  },
  tabsStrip: {
    borderBottomWidth: 0,
  },
  cardNoRadius: {
    borderRadius: 0,
  },
  sheetTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 10,
    paddingTop: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  sheetTitle: {
    fontWeight: '700',
  },
  sheetCloseButton: {
    padding: 6,
    borderRadius: 999,
  },
  sheetContent: {
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 6,
    gap: 10,
  },
  pressed: {
    opacity: 0.7,
  },
});

