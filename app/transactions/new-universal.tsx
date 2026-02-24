import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, LayoutAnimation, Pressable, StyleSheet, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { FormField } from '../../src/components/FormField';
import { FormActions } from '../../src/components/FormActions';
import { ProjectPickerList } from '../../src/components/modals/ProjectPickerList';
import { VendorPicker } from '../../src/components/VendorPicker';
import { MediaGallerySection } from '../../src/components/MediaGallerySection';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { createTransaction } from '../../src/data/transactionsService';
import { saveLocalMedia } from '../../src/offline/media';
import type { AttachmentRef } from '../../src/offline/media';
import { layout } from '../../src/ui';
import { getTextSecondaryStyle } from '../../src/ui/styles/typography';
import { getCardStyle } from '../../src/ui';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type TransactionType = 'purchase' | 'return';
type Destination = { kind: 'inventory' } | { kind: 'project'; projectId: string };
type Channel = 'online' | 'in-store';
type OnlineAction = 'amazon' | 'wayfair' | 'manual';
type ReturnLinkChoice = 'yes' | 'skip';
type RefundMethod = 'purchasing-card' | 'gift-card';

// Steps in the progressive disclosure flow
type Step =
  | 'type'
  | 'destination'
  | 'channel'         // purchase branch
  | 'online-action'   // purchase → online
  | 'link-items'      // return branch
  | 'details';

const BRAND_COLOR = '#987e55';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseCurrency(value: string): number | null {
  const normalized = value.replace(/[^0-9.]/g, '');
  if (!normalized) return null;
  const num = Number.parseFloat(normalized);
  if (Number.isNaN(num)) return null;
  return Math.round(num * 100);
}

function getCompletedStepLabel(step: Step, state: FormState): string | null {
  switch (step) {
    case 'type':
      return state.transactionType === 'purchase' ? 'Purchase' : 'Return';
    case 'destination':
      if (!state.destination) return null;
      return state.destination.kind === 'inventory' ? 'Inventory' : 'Project';
    case 'channel':
      return state.channel === 'online' ? 'Online' : 'In-Store';
    case 'online-action':
      if (state.onlineAction === 'amazon') return 'Amazon Import';
      if (state.onlineAction === 'wayfair') return 'Wayfair Import';
      return 'Create';
    case 'link-items':
      return state.returnLinkChoice === 'yes' ? 'Linked Items' : 'No Items Linked';
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Form state
// ---------------------------------------------------------------------------

type FormState = {
  transactionType: TransactionType | null;
  destination: Destination | null;
  // Purchase branch
  channel: Channel | null;
  onlineAction: OnlineAction | null;
  // Return branch
  returnLinkChoice: ReturnLinkChoice | null;
  linkedItemIds: string[];
  refundMethod: RefundMethod | null;
  // Common details
  source: string;
  transactionDate: string;
  amount: string;
  notes: string;
  purchasedBy: string;
  emailReceipt: string;
  images: string[];
};

const INITIAL_STATE: FormState = {
  transactionType: null,
  destination: null,
  channel: null,
  onlineAction: null,
  returnLinkChoice: null,
  linkedItemIds: [],
  refundMethod: null,
  source: '',
  transactionDate: '',
  amount: '',
  notes: '',
  purchasedBy: '',
  emailReceipt: '',
  images: [],
};

// ---------------------------------------------------------------------------
// Step progression logic
// ---------------------------------------------------------------------------

function getCurrentStep(state: FormState): Step {
  if (!state.transactionType) return 'type';
  if (!state.destination) return 'destination';

  if (state.transactionType === 'purchase') {
    if (!state.channel) return 'channel';
    if (state.channel === 'online' && !state.onlineAction) return 'online-action';
    return 'details';
  }

  // Return flow
  if (!state.returnLinkChoice) return 'link-items';
  return 'details';
}

function getCompletedSteps(state: FormState): Step[] {
  const steps: Step[] = [];
  if (!state.transactionType) return steps;
  steps.push('type');

  if (!state.destination) return steps;
  steps.push('destination');

  if (state.transactionType === 'purchase') {
    if (!state.channel) return steps;
    steps.push('channel');
    if (state.channel === 'online') {
      if (!state.onlineAction) return steps;
      steps.push('online-action');
    }
  } else {
    if (!state.returnLinkChoice) return steps;
    steps.push('link-items');
  }
  return steps;
}

function getTotalSteps(state: FormState): number {
  if (!state.transactionType) return 4; // estimate
  if (state.transactionType === 'purchase') {
    if (state.channel === 'online') return 5; // type, dest, channel, online-action, details
    return 4; // type, dest, channel, details
  }
  return 4; // type, dest, link-items, details
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function NewUniversalTransactionScreen() {
  const router = useRouter();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const accountId = useAccountContextStore((store) => store.accountId);
  const [state, setState] = useState<FormState>(INITIAL_STATE);
  const [error, setError] = useState<string | null>(null);

  const currentStep = getCurrentStep(state);
  const completedSteps = getCompletedSteps(state);
  const totalSteps = getTotalSteps(state);
  const progress = completedSteps.length / totalSteps;

  const update = useCallback((partial: Partial<FormState>) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setState((prev) => ({ ...prev, ...partial }));
  }, []);

  // Reset downstream state when changing an earlier choice
  const resetFrom = useCallback((step: Step) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setState((prev) => {
      const next = { ...prev };
      switch (step) {
        case 'type':
          next.transactionType = null;
          next.destination = null;
          next.channel = null;
          next.onlineAction = null;
          next.returnLinkChoice = null;
          next.linkedItemIds = [];
          next.refundMethod = null;
          break;
        case 'destination':
          next.destination = null;
          next.channel = null;
          next.onlineAction = null;
          next.returnLinkChoice = null;
          next.linkedItemIds = [];
          break;
        case 'channel':
          next.channel = null;
          next.onlineAction = null;
          break;
        case 'online-action':
          next.onlineAction = null;
          break;
        case 'link-items':
          next.returnLinkChoice = null;
          next.linkedItemIds = [];
          break;
      }
      return next;
    });
  }, []);

  const imageAttachments = useMemo<AttachmentRef[]>(
    () => state.images.map((uri) => ({ url: uri, kind: 'image' as const })),
    [state.images],
  );

  const handleAddImage = useCallback((localUri: string) => {
    update({ images: [...state.images, localUri].slice(0, 5) });
  }, [state.images, update]);

  const handleAddImages = useCallback((localUris: string[]) => {
    update({ images: [...state.images, ...localUris].slice(0, 5) });
  }, [state.images, update]);

  const handleRemoveImage = useCallback((attachment: AttachmentRef) => {
    update({ images: state.images.filter((uri) => uri !== attachment.url) });
  }, [state.images, update]);

  // Navigate to invoice import screens
  const handleInvoiceImport = useCallback((provider: 'amazon' | 'wayfair') => {
    if (!state.destination || state.destination.kind !== 'project') {
      Alert.alert('Project Required', 'Invoice import is only available for project transactions.');
      return;
    }
    const projectId = state.destination.projectId;
    router.push(`/project/${projectId}/import-${provider}` as any);
  }, [state.destination, router]);

  // Submit
  const handleSubmit = useCallback(async () => {
    if (!accountId) {
      setError('No account selected.');
      return;
    }
    if (!state.destination) {
      setError('Please select a destination.');
      return;
    }

    setError(null);

    // Save images to local media store
    const savedImages: { url: string; kind: 'image' }[] = [];
    for (const uri of state.images) {
      try {
        const result = await saveLocalMedia({
          localUri: uri,
          mimeType: 'image/jpeg',
          ownerScope: 'transaction:new',
          persistCopy: false,
        });
        savedImages.push({ url: result.attachmentRef.url, kind: 'image' });
      } catch {
        // Skip failed saves
      }
    }

    const amountCents = parseCurrency(state.amount);
    const projectId = state.destination.kind === 'project' ? state.destination.projectId : null;

    const newTxId = createTransaction(accountId, {
      source: state.source.trim() || null,
      transactionDate: state.transactionDate.trim() || null,
      amountCents,
      notes: state.notes.trim() || null,
      transactionType: state.transactionType === 'return' ? 'return' : 'purchase',
      projectId,
      purchasedBy: state.purchasedBy.trim() || null,
      hasEmailReceipt: !!state.emailReceipt.trim(),
      otherImages: savedImages.length > 0 ? savedImages : null,
      needsReview: true,
    });

    // Navigate to the transaction detail screen with showNextSteps flag
    router.replace({
      pathname: '/transactions/[id]',
      params: {
        id: newTxId,
        scope: state.destination.kind === 'project' ? 'project' : 'inventory',
        projectId: projectId ?? '',
        showNextSteps: 'true',
      },
    });
  }, [accountId, state, router]);

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <Screen title="New Transaction" backTarget="/(tabs)/index" hideMenu includeBottomInset={false}>
      {/* Progress bar */}
      <View style={styles.progressBarTrack}>
        <View style={[styles.progressBarFill, { width: `${Math.round(progress * 100)}%`, backgroundColor: BRAND_COLOR }]} />
      </View>

      <AppScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        {/* Completed step breadcrumbs */}
        {completedSteps.length > 0 && (
          <View style={styles.breadcrumbRow}>
            {completedSteps.map((step, index) => (
              <React.Fragment key={step}>
                {index > 0 && (
                  <MaterialIcons name="chevron-right" size={16} color={theme.colors.textSecondary} />
                )}
                <CompletedStepChip
                  label={getCompletedStepLabel(step, state) ?? ''}
                  onPress={() => resetFrom(step)}
                />
              </React.Fragment>
            ))}
          </View>
        )}

        {/* Current step */}
        {currentStep === 'type' && (
          <StepSection title="What type of transaction?">
            <OptionCard
              label="Purchase"
              icon="shopping-cart"
              selected={false}
              onPress={() => update({ transactionType: 'purchase' })}
            />
            <OptionCard
              label="Return"
              icon="assignment-return"
              selected={false}
              onPress={() => update({ transactionType: 'return' })}
            />
          </StepSection>
        )}

        {currentStep === 'destination' && (
          <StepSection title="Where does this belong?">
            <OptionCard
              label="Business Inventory"
              icon="warehouse"
              selected={state.destination?.kind === 'inventory'}
              onPress={() => update({ destination: { kind: 'inventory' } })}
            />
            <View style={styles.divider}>
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>or select a project</AppText>
            </View>
            {accountId ? (
              <ProjectPickerList
                accountId={accountId}
                selectedId={state.destination?.kind === 'project' ? state.destination.projectId : null}
                onSelect={(projectId) => {
                  if (projectId) {
                    update({ destination: { kind: 'project', projectId } });
                  }
                }}
                maxHeight={250}
              />
            ) : null}
          </StepSection>
        )}

        {currentStep === 'channel' && (
          <StepSection title="How was this purchased?">
            <OptionCard
              label="Online"
              icon="language"
              selected={false}
              onPress={() => update({ channel: 'online' })}
            />
            <OptionCard
              label="In-Store"
              icon="store"
              selected={false}
              onPress={() => update({ channel: 'in-store' })}
            />
          </StepSection>
        )}

        {currentStep === 'online-action' && (
          <StepSection title="Import or enter manually?">
            {state.destination?.kind === 'project' ? (
              <>
                <OptionCard
                  label="Import from Amazon"
                  icon="receipt-long"
                  selected={false}
                  onPress={() => handleInvoiceImport('amazon')}
                />
                <OptionCard
                  label="Import from Wayfair"
                  icon="receipt-long"
                  selected={false}
                  onPress={() => handleInvoiceImport('wayfair')}
                />
              </>
            ) : null}
            <OptionCard
              label="Create Manually"
              icon="edit"
              selected={false}
              onPress={() => update({ onlineAction: 'manual' })}
            />
          </StepSection>
        )}

        {currentStep === 'link-items' && (
          <StepSection title="Link items to this return?">
            <OptionCard
              label="Yes, Link Items"
              icon="link"
              selected={false}
              onPress={() => {
                // TODO: Open item picker when SharedItemsList picker mode is integrated
                // For now, skip to manual entry
                Alert.alert(
                  'Coming Soon',
                  'Item linking during return creation will be available soon. You can link items after creating the transaction.',
                  [{ text: 'Continue', onPress: () => update({ returnLinkChoice: 'skip' }) }]
                );
              }}
            />
            <OptionCard
              label="Skip for Now"
              icon="skip-next"
              selected={false}
              onPress={() => update({ returnLinkChoice: 'skip' })}
            />
          </StepSection>
        )}

        {currentStep === 'details' && (
          <View style={styles.detailsSection}>
            <AppText variant="h2" style={styles.sectionTitle}>
              {state.transactionType === 'return' ? 'Return Details' : 'Transaction Details'}
            </AppText>

            {/* Return-specific: refund method */}
            {state.transactionType === 'return' && (
              <View style={styles.fieldGroup}>
                <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>Refund Method</AppText>
                <View style={styles.optionRow}>
                  <SmallOptionChip
                    label="Purchasing Card"
                    selected={state.refundMethod === 'purchasing-card'}
                    onPress={() => update({ refundMethod: 'purchasing-card' })}
                  />
                  <SmallOptionChip
                    label="Gift Card"
                    selected={state.refundMethod === 'gift-card'}
                    onPress={() => update({ refundMethod: 'gift-card' })}
                  />
                </View>
              </View>
            )}

            {accountId ? (
              <VendorPicker
                accountId={accountId}
                value={state.source}
                onChangeValue={(v) => update({ source: v })}
              />
            ) : (
              <FormField
                label="Source"
                value={state.source}
                onChangeText={(v) => update({ source: v })}
                placeholder="e.g. Home Depot, Amazon"
              />
            )}

            <FormField
              label="Date"
              value={state.transactionDate}
              onChangeText={(v) => update({ transactionDate: v })}
              placeholder="YYYY-MM-DD"
            />

            {state.transactionType === 'return' && (
              <FormField
                label="Amount"
                value={state.amount}
                onChangeText={(v) => update({ amount: v })}
                placeholder="$0.00"
                inputProps={{ keyboardType: 'decimal-pad' }}
              />
            )}

            <FormField
              label="Notes"
              value={state.notes}
              onChangeText={(v) => update({ notes: v })}
              placeholder="Add notes..."
              inputProps={{ multiline: true, numberOfLines: 3 }}
            />

            {state.transactionType === 'return' && (
              <>
                <FormField
                  label="Email Receipt"
                  value={state.emailReceipt}
                  onChangeText={(v) => update({ emailReceipt: v })}
                  placeholder="Email address for receipt"
                  inputProps={{ keyboardType: 'email-address', autoCapitalize: 'none' }}
                />
                <FormField
                  label="Purchased By"
                  value={state.purchasedBy}
                  onChangeText={(v) => update({ purchasedBy: v })}
                  placeholder="Who purchased this?"
                />
              </>
            )}

            <MediaGallerySection
              title={state.transactionType === 'purchase' ? 'Photos' : 'Images'}
              attachments={imageAttachments}
              maxAttachments={5}
              onAddAttachment={handleAddImage}
              onAddAttachments={handleAddImages}
              onRemoveAttachment={handleRemoveImage}
              size="sm"
            />

            {error ? (
              <AppText variant="caption" style={{ color: theme.colors.error }}>
                {error}
              </AppText>
            ) : null}
          </View>
        )}
      </AppScrollView>

      {currentStep === 'details' && (
        <FormActions>
          <AppButton
            title="Cancel"
            variant="secondary"
            onPress={() => router.back()}
            style={styles.actionButton}
          />
          <AppButton
            title="Create Transaction"
            onPress={handleSubmit}
            style={styles.actionButton}
          />
        </FormActions>
      )}
    </Screen>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function StepSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.stepSection}>
      <AppText variant="h2" style={styles.sectionTitle}>{title}</AppText>
      <View style={styles.stepOptions}>{children}</View>
    </View>
  );
}

function OptionCard({
  label,
  icon,
  selected,
  onPress,
}: {
  label: string;
  icon: React.ComponentProps<typeof MaterialIcons>['name'];
  selected: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.optionCard,
        {
          borderColor: selected ? theme.colors.primary : uiKitTheme.border.secondary,
          backgroundColor: selected ? uiKitTheme.background.surface : 'transparent',
          opacity: pressed ? 0.7 : 1,
        },
      ]}
    >
      <MaterialIcons name={icon} size={24} color={selected ? theme.colors.primary : theme.colors.textSecondary} />
      <AppText variant="body" style={selected ? { color: theme.colors.primary } : undefined}>
        {label}
      </AppText>
    </Pressable>
  );
}

function CompletedStepChip({ label, onPress }: { label: string; onPress: () => void }) {
  const theme = useTheme();

  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityHint="Tap to change"
      style={({ pressed }) => [
        styles.completedChip,
        {
          backgroundColor: 'transparent',
          opacity: pressed ? 0.6 : 1,
        },
      ]}
    >
      <AppText variant="caption" style={{ color: theme.colors.primary, fontWeight: '600' }}>{label}</AppText>
    </Pressable>
  );
}

function SmallOptionChip({
  label,
  selected,
  onPress,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  return (
    <Pressable
      onPress={onPress}
      style={[
        styles.smallChip,
        {
          borderColor: selected ? theme.colors.primary : uiKitTheme.border.secondary,
          backgroundColor: selected ? uiKitTheme.background.surface : 'transparent',
        },
      ]}
    >
      <AppText variant="caption" style={selected ? { color: theme.colors.primary } : undefined}>
        {label}
      </AppText>
    </Pressable>
  );
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

const styles = StyleSheet.create({
  scroll: {
    flex: 1,
  },
  container: {
    gap: 12,
    paddingTop: layout.screenBodyTopMd.paddingTop,
    paddingBottom: 24,
  },
  progressBarTrack: {
    height: 3,
    backgroundColor: '#E0E0E0',
  },
  progressBarFill: {
    height: 3,
    borderRadius: 1.5,
  },
  stepSection: {
    gap: 12,
  },
  sectionTitle: {
    marginBottom: 4,
  },
  stepOptions: {
    gap: 10,
  },
  optionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: 16,
    paddingHorizontal: 16,
    borderRadius: 12,
    borderWidth: 1,
  },
  breadcrumbRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 4,
  },
  completedChip: {
    paddingVertical: 4,
    paddingHorizontal: 2,
  },
  divider: {
    alignItems: 'center',
    paddingVertical: 4,
  },
  detailsSection: {
    gap: 16,
  },
  fieldGroup: {
    gap: 8,
  },
  optionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  smallChip: {
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 20,
    borderWidth: 1,
  },
  actionButton: {
    flex: 1,
  },
});
