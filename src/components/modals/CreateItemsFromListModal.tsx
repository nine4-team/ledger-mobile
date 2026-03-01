import { useState, useCallback, useMemo } from 'react';
import { StyleSheet, TextInput, View, ScrollView, Pressable } from 'react-native';

import { BottomSheet } from '../BottomSheet';
import { AppButton } from '../AppButton';
import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import { getTextInputStyle } from '../../ui/styles/forms';
import { getTextSecondaryStyle, textEmphasis } from '../../ui/styles/typography';
import { parseReceiptList, type ParsedReceiptItem } from '../../utils/receiptListParser';

export type CreateItemsFromListModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  onCreateItems: (items: ParsedReceiptItem[]) => void;
};

type Step = 'input' | 'preview';

export function CreateItemsFromListModal({
  visible,
  onRequestClose,
  onCreateItems,
}: CreateItemsFromListModalProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const [text, setText] = useState('');
  const [step, setStep] = useState<Step>('input');
  const [parsedItems, setParsedItems] = useState<ParsedReceiptItem[]>([]);
  const [skippedLines, setSkippedLines] = useState<string[]>([]);
  const [skippedExpanded, setSkippedExpanded] = useState(false);

  const themedStyles = useMemo(
    () => ({
      headerBorder: { borderBottomColor: uiKitTheme.border.secondary },
      actionsBorder: { borderTopColor: uiKitTheme.border.secondary },
      description: getTextSecondaryStyle(uiKitTheme),
      rowBorder: { borderBottomColor: uiKitTheme.border.secondary },
    }),
    [uiKitTheme],
  );

  const reset = useCallback(() => {
    setText('');
    setStep('input');
    setParsedItems([]);
    setSkippedLines([]);
    setSkippedExpanded(false);
  }, []);

  const handleClose = useCallback(() => {
    onRequestClose();
    // Delay reset so animation completes
    setTimeout(reset, 300);
  }, [onRequestClose, reset]);

  const handleParse = useCallback(() => {
    const result = parseReceiptList(text);
    setParsedItems(result.items);
    setSkippedLines(result.skippedLines);
    if (result.items.length > 0) {
      setStep('preview');
    }
  }, [text]);

  const handleBack = useCallback(() => {
    setStep('input');
  }, []);

  const handleCreate = useCallback(() => {
    onCreateItems(parsedItems);
    handleClose();
  }, [parsedItems, onCreateItems, handleClose]);

  const formatPrice = (cents: number) => {
    return `$${(cents / 100).toFixed(2)}`;
  };

  const totalCents = useMemo(
    () => parsedItems.reduce((sum, item) => sum + item.priceCents, 0),
    [parsedItems],
  );

  if (!visible) return null;

  return (
    <BottomSheet
      visible={visible}
      onRequestClose={handleClose}
      containerStyle={styles.sheetContainer}
    >
      {/* Header */}
      <View style={[styles.header, themedStyles.headerBorder]}>
        <AppText variant="body" style={[styles.title, textEmphasis.strong]}>
          {step === 'input' ? 'Create Items from List' : 'Preview Items'}
        </AppText>
        {step === 'preview' && (
          <AppText variant="caption" style={themedStyles.description}>
            {parsedItems.length} item{parsedItems.length !== 1 ? 's' : ''} — {formatPrice(totalCents)} total
          </AppText>
        )}
      </View>

      {step === 'input' ? (
        <>
          <View style={styles.content}>
            <TextInput
              value={text}
              onChangeText={setText}
              placeholder="Paste receipt lines here..."
              placeholderTextColor={theme.colors.textSecondary}
              style={[
                getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 }),
                styles.textArea,
              ]}
              multiline
              textAlignVertical="top"
              autoFocus
            />
          </View>
          <View style={[styles.actions, themedStyles.actionsBorder]}>
            <AppButton
              title="Cancel"
              variant="secondary"
              onPress={handleClose}
              style={styles.actionButton}
            />
            <AppButton
              title="Parse List"
              onPress={handleParse}
              disabled={text.trim().length === 0}
              style={styles.actionButton}
            />
          </View>
        </>
      ) : (
        <>
          <ScrollView style={styles.previewScroll} contentContainerStyle={styles.previewContent}>
            {parsedItems.map((item, index) => (
              <View
                key={`${item.sku}-${index}`}
                style={[styles.previewRow, themedStyles.rowBorder]}
              >
                <View style={styles.previewRowLeft}>
                  <AppText variant="body" numberOfLines={1} style={textEmphasis.strong}>
                    {item.name}
                  </AppText>
                  <AppText variant="caption">SKU: {item.sku}</AppText>
                </View>
                <AppText variant="body" style={textEmphasis.strong}>
                  {formatPrice(item.priceCents)}
                </AppText>
              </View>
            ))}
            {skippedLines.length > 0 && (
              <View style={styles.skippedSection}>
                <Pressable onPress={() => setSkippedExpanded((prev) => !prev)}>
                  <AppText variant="caption" style={styles.skippedHeader}>
                    {skippedLines.length} line{skippedLines.length !== 1 ? 's' : ''} could not be parsed{' '}
                    {skippedExpanded ? '▾' : '▸'}
                  </AppText>
                </Pressable>
                {skippedExpanded &&
                  skippedLines.map((line, i) => (
                    <AppText key={i} variant="caption" style={styles.skippedLine}>
                      {line}
                    </AppText>
                  ))}
              </View>
            )}
          </ScrollView>
          <View style={[styles.actions, themedStyles.actionsBorder]}>
            <AppButton
              title="Back"
              variant="secondary"
              onPress={handleBack}
              style={styles.actionButton}
            />
            <AppButton
              title={`Create ${parsedItems.length} Item${parsedItems.length !== 1 ? 's' : ''}`}
              onPress={handleCreate}
              style={styles.actionButton}
            />
          </View>
        </>
      )}
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  sheetContainer: {
    maxHeight: '85%',
  },
  header: {
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {
    fontWeight: '700',
    textAlign: 'center',
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 16,
    flex: 1,
  },
  textArea: {
    minHeight: 200,
    maxHeight: 400,
    fontSize: 14,
  },
  actions: {
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 16,
    paddingTop: 20,
    paddingBottom: 20,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  actionButton: {
    flex: 1,
  },
  previewScroll: {
    maxHeight: 400,
  },
  previewContent: {
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  previewRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  previewRowLeft: {
    flex: 1,
    marginRight: 12,
  },
  skippedSection: {
    marginTop: 12,
    paddingTop: 8,
  },
  skippedHeader: {
    fontStyle: 'italic',
    paddingVertical: 4,
  },
  skippedLine: {
    fontFamily: 'monospace',
    fontSize: 11,
    paddingVertical: 2,
    paddingLeft: 8,
  },
});
