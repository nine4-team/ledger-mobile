import { useState, useCallback, useMemo } from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import MaterialIcons from '@expo/vector-icons/MaterialIcons';

import { BottomSheet } from '../BottomSheet';
import { AppButton } from '../AppButton';
import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import { getTextInputStyle } from '../../ui/styles/forms';
import { getTextSecondaryStyle, textEmphasis } from '../../ui/styles/typography';
import { searchItemsByDescription, type ItemStub, type AiMatchResult } from '../../utils/aiSpaceSearch';

export type AiSpaceSearchModalProps = {
  visible: boolean;
  onRequestClose: () => void;
  /** All items in scope — both already-in-space and available. */
  allItems: ItemStub[];
  /** IDs of items already assigned to this space. */
  spaceItemIds: Set<string>;
  onAddItems: (itemIds: string[]) => void;
};

type Step = 'input' | 'review';

type MatchRow = AiMatchResult & {
  name: string;
  alreadyInSpace: boolean;
  selected: boolean;
};

export function AiSpaceSearchModal({
  visible,
  onRequestClose,
  allItems,
  spaceItemIds,
  onAddItems,
}: AiSpaceSearchModalProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [step, setStep] = useState<Step>('input');
  const [description, setDescription] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [matches, setMatches] = useState<MatchRow[]>([]);
  const [unmatched, setUnmatched] = useState<string[]>([]);

  const themedStyles = useMemo(
    () => ({
      headerBorder: { borderBottomColor: uiKitTheme.border.secondary },
      actionsBorder: { borderTopColor: uiKitTheme.border.secondary },
      description: getTextSecondaryStyle(uiKitTheme),
      rowBorder: { borderBottomColor: uiKitTheme.border.secondary },
      sectionLabel: { color: uiKitTheme.text.secondary },
      checkActive: { color: uiKitTheme.primary.main },
      checkInSpace: { color: '#34C759' }, // system green
      unmatchedBg: { backgroundColor: uiKitTheme.background.screen },
      unmatchedBorder: { borderColor: '#F59E0B' },
    }),
    [uiKitTheme],
  );

  const reset = useCallback(() => {
    setStep('input');
    setDescription('');
    setLoading(false);
    setError(null);
    setMatches([]);
    setUnmatched([]);
  }, []);

  const handleClose = useCallback(() => {
    onRequestClose();
    setTimeout(reset, 300);
  }, [onRequestClose, reset]);

  const handleSearch = useCallback(async () => {
    if (!description.trim()) return;
    setLoading(true);
    setError(null);

    try {
      const result = await searchItemsByDescription(description.trim(), allItems);

      const itemMap = new Map(allItems.map((i) => [i.id, i]));

      const matchRows: MatchRow[] = result.matches
        .filter((m) => itemMap.has(m.itemId))
        .map((m) => ({
          ...m,
          name: itemMap.get(m.itemId)!.name,
          alreadyInSpace: spaceItemIds.has(m.itemId),
          selected: !spaceItemIds.has(m.itemId), // pre-select only items not yet in space
        }));

      if (matchRows.length === 0 && result.unmatched.length === 0) {
        setError('No items matched. Try rephrasing your description.');
        setLoading(false);
        return;
      }

      setMatches(matchRows);
      setUnmatched(result.unmatched);
      setStep('review');
    } catch {
      setError('Something went wrong. Check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }, [description, allItems, spaceItemIds]);

  const toggleMatch = useCallback((itemId: string) => {
    setMatches((prev) =>
      prev.map((m) => (m.itemId === itemId ? { ...m, selected: !m.selected } : m)),
    );
  }, []);

  const handleAdd = useCallback(() => {
    const ids = matches.filter((m) => m.selected && !m.alreadyInSpace).map((m) => m.itemId);
    onAddItems(ids);
    handleClose();
  }, [matches, onAddItems, handleClose]);

  const alreadyInSpace = useMemo(() => matches.filter((m) => m.alreadyInSpace), [matches]);
  const toAdd = useMemo(() => matches.filter((m) => !m.alreadyInSpace), [matches]);
  const selectedCount = useMemo(() => toAdd.filter((m) => m.selected).length, [toAdd]);

  if (!visible) return null;

  return (
    <BottomSheet visible={visible} onRequestClose={handleClose} containerStyle={styles.sheet}>
      {/* Header */}
      <View style={[styles.header, themedStyles.headerBorder]}>
        <AppText variant="body" style={[styles.title, textEmphasis.strong]}>
          {step === 'input' ? 'AI Search' : 'Review Matches'}
        </AppText>
        {step === 'input' && (
          <AppText variant="caption" style={themedStyles.description}>
            Describe what's in this room to find matching items
          </AppText>
        )}
        {step === 'review' && (
          <AppText variant="caption" style={themedStyles.description}>
            {matches.length} match{matches.length !== 1 ? 'es' : ''} found
            {unmatched.length > 0 ? `, ${unmatched.length} not recognized` : ''}
          </AppText>
        )}
      </View>

      {step === 'input' ? (
        <>
          <View style={styles.content}>
            <TextInput
              value={description}
              onChangeText={(t) => {
                setDescription(t);
                if (error) setError(null);
              }}
              placeholder="White linen sofa, oak coffee table, brass floor lamp…"
              placeholderTextColor={theme.colors.textSecondary}
              style={[
                getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 }),
                styles.textArea,
              ]}
              multiline
              textAlignVertical="top"
              autoFocus
            />
            {error && (
              <AppText variant="caption" style={styles.errorText}>
                {error}
              </AppText>
            )}
          </View>
          <View style={[styles.actions, themedStyles.actionsBorder]}>
            <AppButton
              title="Cancel"
              variant="secondary"
              onPress={handleClose}
              style={styles.actionButton}
              disabled={loading}
            />
            <AppButton
              title={loading ? '' : 'Find Items'}
              onPress={handleSearch}
              disabled={description.trim().length === 0 || loading}
              style={styles.actionButton}
              leftIcon={
                loading ? (
                  <ActivityIndicator size="small" color={uiKitTheme.button.primary.text} />
                ) : undefined
              }
            />
          </View>
        </>
      ) : (
        <>
          <ScrollView style={styles.reviewScroll} contentContainerStyle={styles.reviewContent}>
            {alreadyInSpace.length > 0 && (
              <View style={styles.section}>
                <AppText variant="caption" style={[textEmphasis.sectionLabel, themedStyles.sectionLabel]}>
                  Already in This Space
                </AppText>
                {alreadyInSpace.map((m) => (
                  <View key={m.itemId} style={[styles.row, themedStyles.rowBorder]}>
                    <MaterialIcons name="check-circle" size={20} style={themedStyles.checkInSpace} />
                    <AppText variant="body" style={[styles.rowText, styles.rowTextMuted]}>
                      {m.name}
                    </AppText>
                  </View>
                ))}
              </View>
            )}

            {toAdd.length > 0 && (
              <View style={styles.section}>
                <AppText variant="caption" style={[textEmphasis.sectionLabel, themedStyles.sectionLabel]}>
                  Add to Space
                </AppText>
                {toAdd.map((m) => (
                  <TouchableOpacity
                    key={m.itemId}
                    style={[styles.row, themedStyles.rowBorder, !m.selected && styles.rowDeselected]}
                    onPress={() => toggleMatch(m.itemId)}
                    accessibilityRole="checkbox"
                    accessibilityState={{ checked: m.selected }}
                  >
                    <MaterialIcons
                      name={m.selected ? 'check-box' : 'check-box-outline-blank'}
                      size={20}
                      color={m.selected ? uiKitTheme.primary.main : uiKitTheme.text.secondary}
                    />
                    <AppText
                      variant="body"
                      style={[styles.rowText, !m.selected && styles.rowTextMuted]}
                    >
                      {m.name}
                    </AppText>
                  </TouchableOpacity>
                ))}
              </View>
            )}

            {unmatched.length > 0 && (
              <View style={styles.section}>
                <AppText variant="caption" style={[textEmphasis.sectionLabel, themedStyles.sectionLabel]}>
                  Not Found
                </AppText>
                {unmatched.map((phrase, i) => (
                  <View
                    key={i}
                    style={[styles.unmatchedRow, themedStyles.unmatchedBorder]}
                  >
                    <MaterialIcons name="warning-amber" size={16} color="#F59E0B" />
                    <AppText variant="caption" style={styles.unmatchedText}>
                      "{phrase}"
                    </AppText>
                  </View>
                ))}
              </View>
            )}
          </ScrollView>

          <View style={[styles.actions, themedStyles.actionsBorder]}>
            <AppButton
              title="Back"
              variant="secondary"
              onPress={() => setStep('input')}
              style={styles.actionButton}
            />
            <AppButton
              title={
                selectedCount === 0
                  ? 'No Items Selected'
                  : `Add ${selectedCount} Item${selectedCount !== 1 ? 's' : ''}`
              }
              onPress={handleAdd}
              disabled={selectedCount === 0}
              style={styles.actionButton}
            />
          </View>
        </>
      )}
    </BottomSheet>
  );
}

const styles = StyleSheet.create({
  sheet: {
    maxHeight: '88%',
  },
  header: {
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: 4,
  },
  title: {
    fontWeight: '700',
    textAlign: 'center',
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
    paddingBottom: 8,
    flex: 1,
  },
  textArea: {
    minHeight: 180,
    fontSize: 14,
  },
  errorText: {
    color: '#EF4444',
    marginTop: 8,
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
  reviewScroll: {
    maxHeight: 480,
  },
  reviewContent: {
    paddingVertical: 8,
  },
  section: {
    paddingHorizontal: 16,
    paddingTop: 12,
    gap: 0,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 11,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  rowDeselected: {
    opacity: 0.45,
  },
  rowText: {
    flex: 1,
  },
  rowTextMuted: {
    opacity: 0.6,
  },
  unmatchedRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 6,
    paddingHorizontal: 10,
    paddingVertical: 7,
    borderRadius: 8,
    borderWidth: 1,
    borderLeftWidth: 3,
  },
  unmatchedText: {
    flex: 1,
    fontStyle: 'italic',
    color: '#92400E',
  },
});
