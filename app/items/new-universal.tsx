import React, { useCallback, useMemo, useState } from 'react';
import { LayoutAnimation, Pressable, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import * as ImagePicker from 'expo-image-picker';
import { Screen } from '../../src/components/Screen';
import { AppText } from '../../src/components/AppText';
import { AppButton } from '../../src/components/AppButton';
import { AppScrollView } from '../../src/components/AppScrollView';
import { FormField } from '../../src/components/FormField';
import { FormActions } from '../../src/components/FormActions';
import { ProjectPickerList } from '../../src/components/modals/ProjectPickerList';
import { VendorPicker } from '../../src/components/VendorPicker';
import { SpaceSelector } from '../../src/components/SpaceSelector';
import { MediaGallerySection } from '../../src/components/MediaGallerySection';
import { useAccountContextStore } from '../../src/auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../../src/theme/ThemeProvider';
import { createItem } from '../../src/data/itemsService';
import { saveLocalMedia } from '../../src/offline/media';
import type { AttachmentRef } from '../../src/offline/media';
import { layout } from '../../src/ui';
import { getTextSecondaryStyle } from '../../src/ui/styles/typography';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type Destination = { kind: 'inventory' } | { kind: 'project'; projectId: string };
type CaptureMethod = 'photo' | 'manual';

type Step = 'destination' | 'capture' | 'details';

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
    case 'destination':
      if (!state.destination) return null;
      return state.destination.kind === 'inventory' ? 'Inventory' : 'Project';
    case 'capture':
      return state.captureMethod === 'photo' ? 'Photo' : 'Manual';
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Form state
// ---------------------------------------------------------------------------

type FormState = {
  destination: Destination | null;
  captureMethod: CaptureMethod | null;
  // Details
  name: string;
  source: string;
  sku: string;
  purchasePrice: string;
  projectPrice: string;
  quantity: string;
  spaceId: string | null;
  notes: string;
  images: string[];
};

const INITIAL_STATE: FormState = {
  destination: null,
  captureMethod: null,
  name: '',
  source: '',
  sku: '',
  purchasePrice: '',
  projectPrice: '',
  quantity: '1',
  spaceId: null,
  notes: '',
  images: [],
};

// ---------------------------------------------------------------------------
// Step progression
// ---------------------------------------------------------------------------

function getCurrentStep(state: FormState): Step {
  if (!state.destination) return 'destination';
  if (!state.captureMethod) return 'capture';
  return 'details';
}

function getCompletedSteps(state: FormState): Step[] {
  const steps: Step[] = [];
  if (!state.destination) return steps;
  steps.push('destination');
  if (!state.captureMethod) return steps;
  steps.push('capture');
  return steps;
}

const TOTAL_STEPS = 3; // destination, capture, details

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function NewUniversalItemScreen() {
  const router = useRouter();
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();
  const accountId = useAccountContextStore((store) => store.accountId);
  const [state, setState] = useState<FormState>(INITIAL_STATE);
  const [error, setError] = useState<string | null>(null);

  const currentStep = getCurrentStep(state);
  const completedSteps = getCompletedSteps(state);
  const progress = completedSteps.length / TOTAL_STEPS;

  const update = useCallback((partial: Partial<FormState>) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setState((prev) => ({ ...prev, ...partial }));
  }, []);

  const resetFrom = useCallback((step: Step) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setState((prev) => {
      const next = { ...prev };
      switch (step) {
        case 'destination':
          next.destination = null;
          next.captureMethod = null;
          break;
        case 'capture':
          next.captureMethod = null;
          break;
      }
      return next;
    });
  }, []);

  // --- Image handling ---

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

  // --- Capture method: photo launches gallery then advances ---

  const handlePhotoCaptureComplete = useCallback((localUris: string[]) => {
    if (localUris.length > 0) {
      setState((prev) => ({
        ...prev,
        captureMethod: 'photo',
        images: [...prev.images, ...localUris].slice(0, 5),
      }));
      LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    }
  }, []);

  // --- Submit ---

  const handleSubmit = useCallback(async () => {
    if (!accountId) {
      setError('No account selected.');
      return;
    }
    if (!state.destination) {
      setError('Please select a destination.');
      return;
    }
    if (!state.name.trim() && state.images.length === 0) {
      setError('Add a name or at least one photo.');
      return;
    }

    setError(null);

    // Save images to local media store
    const savedImages: { url: string; kind: 'image'; isPrimary?: boolean }[] = [];
    for (const uri of state.images) {
      try {
        const result = await saveLocalMedia({
          localUri: uri,
          mimeType: 'image/jpeg',
          ownerScope: 'item:new',
          persistCopy: false,
        });
        savedImages.push({
          url: result.attachmentRef.url,
          kind: 'image',
          ...(savedImages.length === 0 ? { isPrimary: true } : {}),
        });
      } catch {
        // Skip failed saves
      }
    }

    const purchasePriceCents = parseCurrency(state.purchasePrice);
    const projectPriceCents = parseCurrency(state.projectPrice);
    const projectId = state.destination.kind === 'project' ? state.destination.projectId : null;
    const qty = Math.max(1, Number.parseInt(state.quantity || '1', 10) || 1);

    const payload = {
      name: state.name.trim(),
      sku: state.sku.trim() || null,
      source: state.source.trim() || null,
      purchasePriceCents,
      projectPriceCents,
      projectId,
      spaceId: state.spaceId,
      notes: state.notes.trim() || null,
      images: savedImages.length > 0 ? savedImages : null,
    };

    let lastItemId = '';
    for (let i = 0; i < qty; i++) {
      lastItemId = createItem(accountId, payload);
    }

    // Navigate to the item detail screen
    router.replace({
      pathname: '/items/[id]',
      params: {
        id: lastItemId,
        scope: state.destination.kind === 'project' ? 'project' : 'inventory',
        projectId: projectId ?? '',
      },
    });
  }, [accountId, state, router]);

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <Screen title="New Item" backTarget="/(tabs)/index" hideMenu includeBottomInset={false}>
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

        {/* Step 1: Destination */}
        {currentStep === 'destination' && (
          <StepSection title="Where does this item belong?">
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

        {/* Step 2: Capture method */}
        {currentStep === 'capture' && (
          <StepSection title="How do you want to start?">
            <PhotoCaptureCard onPhotosSelected={handlePhotoCaptureComplete} />
            <OptionCard
              label="Enter Details Manually"
              icon="edit"
              selected={false}
              onPress={() => update({ captureMethod: 'manual' })}
            />
          </StepSection>
        )}

        {/* Step 3: Details form */}
        {currentStep === 'details' && (
          <View style={styles.detailsSection}>
            <AppText variant="h2" style={styles.sectionTitle}>Item Details</AppText>

            <FormField
              label="Name"
              value={state.name}
              onChangeText={(v) => update({ name: v })}
              placeholder="Item name or description"
              helperText={state.images.length > 0 ? undefined : 'Required if no photo added'}
            />

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
              label="SKU"
              value={state.sku}
              onChangeText={(v) => update({ sku: v })}
              placeholder="Model number or SKU"
            />

            <View style={styles.row}>
              <View style={styles.half}>
                <FormField
                  label="Purchase Price"
                  value={state.purchasePrice}
                  onChangeText={(v) => update({ purchasePrice: v })}
                  placeholder="$0.00"
                  inputProps={{ keyboardType: 'decimal-pad' }}
                />
              </View>
              {state.destination?.kind === 'project' && (
                <View style={styles.half}>
                  <FormField
                    label="Project Price"
                    value={state.projectPrice}
                    onChangeText={(v) => update({ projectPrice: v })}
                    placeholder="$0.00"
                    inputProps={{ keyboardType: 'decimal-pad' }}
                  />
                </View>
              )}
            </View>

            <FormField
              label="Quantity"
              value={state.quantity}
              onChangeText={(v) => update({ quantity: v })}
              placeholder="1"
              helperText="Creates multiple identical items"
              inputProps={{ keyboardType: 'number-pad' }}
            />

            <View style={styles.fieldGroup}>
              <AppText variant="caption" style={getTextSecondaryStyle(uiKitTheme)}>Space</AppText>
              <SpaceSelector
                projectId={state.destination?.kind === 'project' ? state.destination.projectId : null}
                value={state.spaceId}
                onChange={(v) => update({ spaceId: v })}
                allowCreate
                placeholder="Select space (optional)"
              />
            </View>

            <MediaGallerySection
              title="Photos"
              attachments={imageAttachments}
              maxAttachments={5}
              onAddAttachment={handleAddImage}
              onAddAttachments={handleAddImages}
              onRemoveAttachment={handleRemoveImage}
              size="sm"
            />

            <FormField
              label="Notes"
              value={state.notes}
              onChangeText={(v) => update({ notes: v })}
              placeholder="Add notes..."
              inputProps={{ multiline: true, numberOfLines: 3 }}
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
            title="Create Item"
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

/**
 * A card that launches the image picker directly.
 * When photos are selected, it calls onPhotosSelected so the parent
 * can advance the step and populate images in one move.
 */
function PhotoCaptureCard({ onPhotosSelected }: { onPhotosSelected: (uris: string[]) => void }) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const handlePress = useCallback(async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsMultipleSelection: true,
      quality: 0.8,
      selectionLimit: 5,
    });
    if (!result.canceled && result.assets.length > 0) {
      onPhotosSelected(result.assets.map((a) => a.uri));
    }
  }, [onPhotosSelected]);

  return (
    <Pressable
      onPress={handlePress}
      style={({ pressed }) => [
        styles.optionCard,
        {
          borderColor: uiKitTheme.border.secondary,
          backgroundColor: 'transparent',
          opacity: pressed ? 0.7 : 1,
        },
      ]}
    >
      <MaterialIcons name="photo-camera" size={24} color={theme.colors.textSecondary} />
      <AppText variant="body">Take a Photo or Choose from Library</AppText>
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
    gap: 6,
  },
  row: {
    flexDirection: 'row',
    gap: 12,
  },
  half: {
    flex: 1,
  },
  actionButton: {
    flex: 1,
  },
});
