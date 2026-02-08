import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';
import { AppText } from './AppText';
import { BottomSheet } from './BottomSheet';
import { AppScrollView } from './AppScrollView';
import { useAccountContextStore } from '../auth/accountContextStore';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
import { createSpace, subscribeToSpaces, type Space } from '../data/spacesService';

export interface SpaceSelectorProps {
  projectId: string | null;
  value: string | null;
  onChange: (spaceId: string | null) => void;
  allowCreate?: boolean;
  disabled?: boolean;
  placeholder?: string;
}

/**
 * SpaceSelector - A dropdown/bottom sheet component for selecting or creating spaces
 *
 * Features:
 * - Shows existing spaces for the current workspace (project or Business Inventory)
 * - Search filters spaces by name (debounced 300ms)
 * - "Create '[typed name]'" option when no exact match exists
 * - Inline space creation with optimistic UI
 * - Works offline with queued writes
 */
export function SpaceSelector({
  projectId,
  value,
  onChange,
  allowCreate = true,
  disabled = false,
  placeholder = 'Select space',
}: SpaceSelectorProps) {
  const accountId = useAccountContextStore((store) => store.accountId);
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [spaces, setSpaces] = useState<Space[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [searchText, setSearchText] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [error, setError] = useState<string | null>(null);

  // Subscribe to spaces for the current workspace
  useEffect(() => {
    if (!accountId) {
      setSpaces([]);
      return () => {};
    }
    return subscribeToSpaces(accountId, projectId, (next) => {
      setSpaces(next);
    });
  }, [accountId, projectId]);

  // Debounce search input (300ms)
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(searchText);
    }, 300);
    return () => clearTimeout(timer);
  }, [searchText]);

  // Get the currently selected space
  const selectedSpace = useMemo(() => {
    return spaces.find((s) => s.id === value) ?? null;
  }, [spaces, value]);

  // Filter spaces by search text
  const filteredSpaces = useMemo(() => {
    if (!debouncedSearch.trim()) {
      return spaces;
    }
    const searchLower = debouncedSearch.toLowerCase();
    return spaces.filter((space) =>
      space.name.toLowerCase().includes(searchLower)
    );
  }, [spaces, debouncedSearch]);

  // Check if search text exactly matches an existing space
  const hasExactMatch = useMemo(() => {
    const searchTrimmed = debouncedSearch.trim();
    if (!searchTrimmed) return false;
    return filteredSpaces.some(
      (space) => space.name.toLowerCase() === searchTrimmed.toLowerCase()
    );
  }, [filteredSpaces, debouncedSearch]);

  // Show "Create '[name]'" option when appropriate
  const showCreateOption = useMemo(() => {
    return (
      allowCreate &&
      debouncedSearch.trim() &&
      !hasExactMatch
    );
  }, [allowCreate, debouncedSearch, hasExactMatch]);

  const handleOpen = useCallback(() => {
    if (!disabled) {
      setIsOpen(true);
      setSearchText('');
      setError(null);
    }
  }, [disabled]);

  const handleClose = useCallback(() => {
    setIsOpen(false);
    setSearchText('');
    setError(null);
  }, []);

  const handleSelectSpace = useCallback(
    (spaceId: string | null) => {
      onChange(spaceId);
      handleClose();
    },
    [onChange, handleClose]
  );

  const handleCreateSpace = useCallback(() => {
    if (!accountId || !debouncedSearch.trim()) return;

    const newName = debouncedSearch.trim();
    setError(null);

    const newSpaceId = createSpace(accountId, {
      name: newName,
      notes: '',
      projectId,
    });

    onChange(newSpaceId);
    handleClose();
  }, [accountId, debouncedSearch, projectId, onChange, handleClose]);

  const displayValue = selectedSpace?.name ?? placeholder;
  const showClearButton = value !== null && !disabled;

  return (
    <View style={styles.container}>
      <Pressable
        onPress={handleOpen}
        disabled={disabled}
        style={({ pressed }) => [
          styles.trigger,
          getTextInputStyle(uiKitTheme, { padding: 12, radius: 10 }),
          disabled && styles.disabled,
          pressed && !disabled && styles.pressed,
        ]}
        accessibilityRole="button"
        accessibilityLabel={`Space: ${displayValue}`}
      >
        <AppText
          variant="body"
          style={[
            styles.triggerText,
            !selectedSpace && { color: theme.colors.textSecondary },
          ]}
          numberOfLines={1}
        >
          {displayValue}
        </AppText>
        <View style={styles.triggerRight}>
          {showClearButton && (
            <Pressable
              onPress={(e) => {
                e.stopPropagation();
                onChange(null);
              }}
              hitSlop={8}
              style={styles.clearButton}
              accessibilityRole="button"
              accessibilityLabel="Clear space"
            >
              <MaterialIcons
                name="close"
                size={18}
                color={uiKitTheme.text.secondary}
              />
            </Pressable>
          )}
          <MaterialIcons
            name="expand-more"
            size={20}
            color={uiKitTheme.text.secondary}
          />
        </View>
      </Pressable>

      <BottomSheet visible={isOpen} onRequestClose={handleClose}>
        <View style={styles.sheetContent}>
          <View style={[styles.titleRow, { borderBottomColor: uiKitTheme.border.secondary }]}>
            <AppText variant="body" style={styles.title}>
              Select space
            </AppText>
          </View>

          <View style={styles.searchContainer}>
            <MaterialIcons
              name="search"
              size={20}
              color={uiKitTheme.text.secondary}
              style={styles.searchIcon}
            />
            <TextInput
              value={searchText}
              onChangeText={setSearchText}
              placeholder="Search or create..."
              placeholderTextColor={theme.colors.textSecondary}
              style={[
                styles.searchInput,
                getTextInputStyle(uiKitTheme, { padding: 10, radius: 8 }),
              ]}
              autoFocus
              autoCapitalize="words"
              autoCorrect={false}
            />
          </View>

          {error && (
            <View style={styles.errorContainer}>
              <AppText variant="caption" style={{ color: uiKitTheme.status.missed.text }}>
                {error}
              </AppText>
            </View>
          )}

          <AppScrollView
            style={styles.optionsList}
            contentContainerStyle={styles.optionsContent}
          >
            {/* Clear selection option */}
            {value !== null && (
              <>
                <Pressable
                  onPress={() => handleSelectSpace(null)}
                  style={({ pressed }) => [
                    styles.option,
                    pressed && styles.optionPressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel="No space"
                >
                  <AppText
                    variant="body"
                    style={[styles.optionText, { color: uiKitTheme.text.secondary }]}
                  >
                    None
                  </AppText>
                  {value === null && (
                    <MaterialIcons
                      name="check"
                      size={20}
                      color={uiKitTheme.primary.main}
                    />
                  )}
                </Pressable>
                <View style={[styles.divider, { backgroundColor: uiKitTheme.border.secondary }]} />
              </>
            )}

            {/* Create new space option */}
            {showCreateOption && (
              <>
                <Pressable
                  onPress={handleCreateSpace}
                  style={({ pressed }) => [
                    styles.option,
                    styles.createOption,
                    pressed && styles.optionPressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel={`Create space "${debouncedSearch.trim()}"`}
                >
                  <View style={styles.createOptionLeft}>
                    <MaterialIcons
                      name="add-circle-outline"
                      size={20}
                      color={uiKitTheme.primary.main}
                    />
                    <AppText
                      variant="body"
                      style={[styles.optionText, { color: uiKitTheme.primary.main }]}
                    >
                      Create "{debouncedSearch.trim()}"
                    </AppText>
                  </View>
                </Pressable>
                <View style={[styles.divider, { backgroundColor: uiKitTheme.border.secondary }]} />
              </>
            )}

            {/* Existing spaces */}
            {filteredSpaces.length > 0 ? (
              filteredSpaces.map((space, index) => {
                const isSelected = space.id === value;
                const showDivider = index < filteredSpaces.length - 1;

                return (
                  <View key={space.id}>
                    <Pressable
                      onPress={() => handleSelectSpace(space.id)}
                      style={({ pressed }) => [
                        styles.option,
                        pressed && styles.optionPressed,
                      ]}
                      accessibilityRole="button"
                      accessibilityLabel={space.name}
                    >
                      <AppText
                        variant="body"
                        style={[
                          styles.optionText,
                          isSelected && { color: uiKitTheme.primary.main },
                        ]}
                        numberOfLines={1}
                      >
                        {space.name}
                      </AppText>
                      {isSelected && (
                        <MaterialIcons
                          name="check"
                          size={20}
                          color={uiKitTheme.primary.main}
                        />
                      )}
                    </Pressable>
                    {showDivider && (
                      <View style={[styles.divider, { backgroundColor: uiKitTheme.border.secondary }]} />
                    )}
                  </View>
                );
              })
            ) : debouncedSearch.trim() ? (
              <View style={styles.emptyState}>
                <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
                  No spaces found
                </AppText>
              </View>
            ) : (
              <View style={styles.emptyState}>
                <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
                  No spaces yet
                </AppText>
              </View>
            )}
          </AppScrollView>
        </View>
      </BottomSheet>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
  },
  trigger: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
  },
  triggerText: {
    flex: 1,
  },
  triggerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  clearButton: {
    padding: 4,
  },
  disabled: {
    opacity: 0.5,
  },
  pressed: {
    opacity: 0.7,
  },
  sheetContent: {
    maxHeight: 500,
  },
  titleRow: {
    paddingHorizontal: 16,
    paddingBottom: 10,
    paddingTop: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {
    fontSize: 16,
    fontWeight: '700',
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 8,
  },
  searchIcon: {
    marginLeft: 4,
  },
  searchInput: {
    flex: 1,
    minHeight: 40,
  },
  errorContainer: {
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  optionsList: {
    maxHeight: 360,
  },
  optionsContent: {
    paddingBottom: 8,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
    minHeight: 48,
  },
  createOption: {
    backgroundColor: 'transparent',
  },
  createOptionLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flex: 1,
  },
  optionPressed: {
    opacity: 0.7,
  },
  optionText: {
    fontSize: 14,
    fontWeight: '500',
    flex: 1,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    opacity: 0.8,
  },
  emptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 24,
    gap: 8,
  },
});
