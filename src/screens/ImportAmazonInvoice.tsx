import React, { useCallback, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import * as DocumentPicker from 'expo-document-picker';
import { Screen } from '../components/Screen';
import { AppText } from '../components/AppText';
import { useTheme } from '../theme/ThemeProvider';
import { useAccountContextStore } from '../auth/accountContextStore';
import { layout } from '../ui';
import {
  PdfExtractionBridge,
  type PdfExtractionBridgeRef,
  type PdfTextResult,
} from '../invoice-import/PdfExtractionBridge';
import { parseAmazonInvoiceText, type AmazonInvoiceParseResult } from '../utils/amazonInvoiceParser';
import { parseMoneyToNumber } from '../utils/money';
import { createRequestDoc, generateRequestOpId } from '../data/requestDocs';
import { saveLocalMedia, enqueueUpload } from '../offline/media';
import { ParsedInvoiceSummary } from '../components/import/ParsedInvoiceSummary';
import { DraftItemsList, type DraftLineItem } from '../components/import/DraftItemsList';
import { ParseDebugReport } from '../components/import/ParseDebugReport';

type ImportAmazonInvoiceProps = {
  projectId: string;
};

export function ImportAmazonInvoice({ projectId }: ImportAmazonInvoiceProps) {
  const router = useRouter();
  const theme = useTheme();
  const accountId = useAccountContextStore((s) => s.accountId);
  const bridgeRef = useRef<PdfExtractionBridgeRef>(null);

  const [isLoading, setIsLoading] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [selectedFileUri, setSelectedFileUri] = useState<string | null>(null);
  const [textResult, setTextResult] = useState<PdfTextResult | null>(null);
  const [parseResult, setParseResult] = useState<AmazonInvoiceParseResult | null>(null);
  const [draftItems, setDraftItems] = useState<DraftLineItem[]>([]);
  const [wrongVendorWarning, setWrongVendorWarning] = useState<string | null>(null);

  const handleSelectPdf = useCallback(async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({ type: 'application/pdf' });
      if (result.canceled || !result.assets?.[0]) return;

      const asset = result.assets[0];
      setSelectedFileUri(asset.uri);
      setIsLoading(true);
      setParseResult(null);
      setDraftItems([]);
      setWrongVendorWarning(null);

      const extracted = await bridgeRef.current?.extractText(asset.uri);
      if (!extracted) {
        Alert.alert('Error', 'PDF extraction bridge is not ready. Please try again.');
        setIsLoading(false);
        return;
      }

      setTextResult(extracted);
      const fullText = extracted.fullText;

      // Check for wrong vendor
      if (/wayfair/i.test(fullText)) {
        setWrongVendorWarning(
          'This PDF appears to be a Wayfair invoice. Consider using the Wayfair import instead.',
        );
      }

      const parsed = parseAmazonInvoiceText(fullText);
      setParseResult(parsed);

      // Map line items to draft items
      const drafts: DraftLineItem[] = parsed.lineItems.map((li) => ({
        description: li.description,
        qty: li.qty,
        unitPrice: li.unitPrice ?? '0.00',
        total: li.total,
        isIncluded: true,
      }));
      setDraftItems(drafts);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to process PDF.';
      Alert.alert('Error', message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const handleItemChange = useCallback((index: number, updates: Partial<DraftLineItem>) => {
    setDraftItems((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], ...updates };
      return next;
    });
  }, []);

  const handleItemRemove = useCallback((index: number) => {
    setDraftItems((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const handleCreateTransaction = useCallback(async () => {
    if (!accountId) {
      Alert.alert('Error', 'No account context. Please sign in.');
      return;
    }
    if (!parseResult) return;

    const includedItems = draftItems.filter((item) => item.isIncluded);
    if (includedItems.length === 0) {
      Alert.alert('No Items', 'Please include at least one item to create a transaction.');
      return;
    }

    setIsCreating(true);
    try {
      const opId = generateRequestOpId();

      createRequestDoc(
        'import-invoice',
        {
          vendor: 'amazon',
          projectId,
          transaction: {
            source: parseResult.orderNumber
              ? `Amazon #${parseResult.orderNumber}`
              : 'Amazon',
            transactionDate: parseResult.orderPlacedDate,
            amountCents: Math.round(
              (parseMoneyToNumber(parseResult.grandTotal ?? '0') ?? 0) * 100,
            ),
            reimbursementType: 'owed-to-company',
          },
          items: includedItems.map((item) => ({
            name: item.description,
            projectPriceCents: Math.round((parseMoneyToNumber(item.total) ?? 0) * 100),
            qty: item.qty,
          })),
          receiptFileUri: selectedFileUri,
        },
        { accountId, projectId },
        opId,
      );

      // Save receipt PDF to offline media store
      if (selectedFileUri) {
        const mediaRecord = await saveLocalMedia({
          localUri: selectedFileUri,
          mimeType: 'application/pdf',
          ownerScope: `project/${projectId}`,
        });
        await enqueueUpload({
          mediaId: mediaRecord.mediaId,
          destinationPath: `accounts/${accountId}/projects/${projectId}/receipts/${opId}.pdf`,
        });
      }

      router.back();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create transaction.';
      Alert.alert('Error', message);
    } finally {
      setIsCreating(false);
    }
  }, [accountId, draftItems, parseResult, projectId, router, selectedFileUri]);

  return (
    <Screen title="Import Amazon Invoice">
      <PdfExtractionBridge ref={bridgeRef} />
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        <View style={[styles.container, { paddingTop: layout.screenBodyTopMd.paddingTop }]}>
          {/* Select PDF button */}
          <TouchableOpacity
            onPress={handleSelectPdf}
            style={[styles.selectButton, { borderColor: theme.colors.primary }]}
            activeOpacity={0.7}
            disabled={isLoading}
          >
            <AppText variant="body" style={{ color: theme.colors.primary }}>
              {selectedFileUri ? 'Select Different PDF' : 'Select PDF'}
            </AppText>
          </TouchableOpacity>

          {/* Loading state */}
          {isLoading && (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={theme.colors.primary} />
              <AppText variant="body">Extracting text from PDF...</AppText>
            </View>
          )}

          {/* Wrong vendor warning */}
          {wrongVendorWarning && (
            <View style={[styles.warningBanner, { backgroundColor: theme.colors.error + '15' }]}>
              <AppText variant="body" style={{ color: theme.colors.error }}>
                {wrongVendorWarning}
              </AppText>
            </View>
          )}

          {/* Parse results */}
          {parseResult && (
            <>
              <ParsedInvoiceSummary
                vendor="amazon"
                orderNumber={parseResult.orderNumber}
                orderDate={parseResult.orderPlacedDate}
                grandTotal={parseResult.grandTotal}
                itemCount={draftItems.length}
                warnings={parseResult.warnings}
              />

              <AppText variant="h2" style={styles.sectionTitle}>
                Line Items
              </AppText>

              <DraftItemsList
                items={draftItems}
                onItemChange={handleItemChange}
                onItemRemove={handleItemRemove}
                vendor="amazon"
              />

              {/* Create Transaction button */}
              <TouchableOpacity
                onPress={handleCreateTransaction}
                style={[styles.createButton, { backgroundColor: theme.colors.primary }]}
                activeOpacity={0.7}
                disabled={isCreating}
              >
                {isCreating ? (
                  <ActivityIndicator size="small" color="#FFFFFF" />
                ) : (
                  <AppText variant="body" style={styles.createButtonText}>
                    Create Transaction
                  </AppText>
                )}
              </TouchableOpacity>
            </>
          )}

          {/* Debug report */}
          {textResult && parseResult && (
            <ParseDebugReport
              rawText={textResult.fullText}
              stats={textResult.stats}
              parseResult={parseResult}
            />
          )}
        </View>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    flexGrow: 1,
  },
  container: {
    gap: 16,
    paddingBottom: 40,
  },
  selectButton: {
    borderWidth: 2,
    borderRadius: 10,
    borderStyle: 'dashed',
    paddingVertical: 20,
    alignItems: 'center',
  },
  loadingContainer: {
    alignItems: 'center',
    gap: 8,
    paddingVertical: 16,
  },
  warningBanner: {
    padding: 12,
    borderRadius: 8,
  },
  sectionTitle: {
    marginTop: 8,
  },
  createButton: {
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 8,
  },
  createButtonText: {
    color: '#FFFFFF',
    fontWeight: '700',
  },
});
