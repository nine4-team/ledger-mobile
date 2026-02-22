import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';
import { AppText } from './AppText';
import { BottomSheet } from './BottomSheet';
import { AppScrollView } from './AppScrollView';
import { useTheme, useUIKitTheme } from '../theme/ThemeProvider';
import { getTextInputStyle } from '../ui/styles/forms';
import { subscribeToProjects, type ProjectSummary } from '../data/scopedListData';

export interface ProjectSelectorProps {
  accountId: string;
  value: string | null;
  onChange: (projectId: string | null) => void;
  excludeProjectId?: string;
  disabled?: boolean;
  placeholder?: string;
}

/**
 * ProjectSelector - A dropdown/bottom sheet component for selecting a project
 *
 * Features:
 * - Shows existing projects for the given account
 * - Filters out archived projects and an optional excludeProjectId
 * - Search filters projects by name (debounced 300ms)
 * - "None" option to clear selection
 * - Works offline with queued writes
 */
export function ProjectSelector({
  accountId,
  value,
  onChange,
  excludeProjectId,
  disabled = false,
  placeholder = 'Select project',
}: ProjectSelectorProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [searchText, setSearchText] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Subscribe to projects for the given account
  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      return () => {};
    }
    return subscribeToProjects(accountId, (next) => {
      setProjects(next);
    });
  }, [accountId]);

  // Debounce search input (300ms)
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(searchText);
    }, 300);
    return () => clearTimeout(timer);
  }, [searchText]);

  // Filter out archived projects and excludeProjectId
  const availableProjects = useMemo(() => {
    return projects.filter((p) => {
      if (p.isArchived === true) return false;
      if (excludeProjectId && p.id === excludeProjectId) return false;
      return true;
    });
  }, [projects, excludeProjectId]);

  // Get the currently selected project
  const selectedProject = useMemo(() => {
    return availableProjects.find((p) => p.id === value) ?? null;
  }, [availableProjects, value]);

  // Filter projects by search text
  const filteredProjects = useMemo(() => {
    if (!debouncedSearch.trim()) {
      return availableProjects;
    }
    const searchLower = debouncedSearch.toLowerCase();
    return availableProjects.filter((project) =>
      (project.name ?? '').toLowerCase().includes(searchLower)
    );
  }, [availableProjects, debouncedSearch]);

  const handleOpen = useCallback(() => {
    if (!disabled) {
      setIsOpen(true);
      setSearchText('');
    }
  }, [disabled]);

  const handleClose = useCallback(() => {
    setIsOpen(false);
    setSearchText('');
  }, []);

  const handleSelectProject = useCallback(
    (projectId: string | null) => {
      onChange(projectId);
      handleClose();
    },
    [onChange, handleClose]
  );

  const displayValue = selectedProject?.name ?? placeholder;
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
        accessibilityLabel={`Project: ${displayValue}`}
      >
        <AppText
          variant="body"
          style={[
            styles.triggerText,
            !selectedProject && { color: theme.colors.textSecondary },
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
              accessibilityLabel="Clear project"
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
              Select project
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
              placeholder="Search projects..."
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

          <AppScrollView
            style={styles.optionsList}
            contentContainerStyle={styles.optionsContent}
          >
            {/* Clear selection option */}
            {value !== null && (
              <>
                <Pressable
                  onPress={() => handleSelectProject(null)}
                  style={({ pressed }) => [
                    styles.option,
                    pressed && styles.optionPressed,
                  ]}
                  accessibilityRole="button"
                  accessibilityLabel="No project"
                >
                  <AppText
                    variant="body"
                    style={[styles.optionText, { color: uiKitTheme.text.secondary }]}
                  >
                    None
                  </AppText>
                </Pressable>
                <View style={[styles.divider, { backgroundColor: uiKitTheme.border.secondary }]} />
              </>
            )}

            {/* Existing projects */}
            {filteredProjects.length > 0 ? (
              filteredProjects.map((project, index) => {
                const isSelected = project.id === value;
                const showDivider = index < filteredProjects.length - 1;

                return (
                  <View key={project.id}>
                    <Pressable
                      onPress={() => handleSelectProject(project.id)}
                      style={({ pressed }) => [
                        styles.option,
                        pressed && styles.optionPressed,
                      ]}
                      accessibilityRole="button"
                      accessibilityLabel={project.name ?? undefined}
                    >
                      <AppText
                        variant="body"
                        style={[
                          styles.optionText,
                          isSelected && { color: uiKitTheme.primary.main },
                        ]}
                        numberOfLines={1}
                      >
                        {project.name ?? ''}
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
                  No projects found
                </AppText>
              </View>
            ) : (
              <View style={styles.emptyState}>
                <AppText variant="caption" style={{ color: uiKitTheme.text.secondary }}>
                  No projects yet
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
