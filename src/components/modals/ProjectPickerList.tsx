import React, { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '../AppText';
import { useTheme, useUIKitTheme } from '../../theme/ThemeProvider';
import { subscribeToProjects, type ProjectSummary } from '../../data/scopedListData';

export interface ProjectPickerListProps {
  accountId: string;
  excludeProjectId?: string;
  selectedId: string | null;
  onSelect: (projectId: string | null) => void;
  maxHeight?: number;
  emptyMessage?: string;
}

export function ProjectPickerList({
  accountId,
  excludeProjectId,
  selectedId,
  onSelect,
  maxHeight = 200,
  emptyMessage = 'No projects available',
}: ProjectPickerListProps) {
  const theme = useTheme();
  const uiKitTheme = useUIKitTheme();

  const [projects, setProjects] = useState<ProjectSummary[]>([]);

  useEffect(() => {
    if (!accountId) {
      setProjects([]);
      return () => {};
    }
    return subscribeToProjects(accountId, (next) => {
      setProjects(next);
    });
  }, [accountId]);

  const available = useMemo(() => {
    return projects
      .filter((p) => {
        if (p.isArchived === true) return false;
        if (excludeProjectId && p.id === excludeProjectId) return false;
        return true;
      })
      .sort((a, b) => (a.name ?? '').localeCompare(b.name ?? ''));
  }, [projects, excludeProjectId]);

  if (available.length === 0) {
    return <AppText variant="caption">{emptyMessage}</AppText>;
  }

  return (
    <ScrollView style={{ maxHeight }}>
      <View style={styles.list}>
        {available.map((project) => {
          const isSelected = selectedId === project.id;
          return (
            <Pressable
              key={project.id}
              onPress={() => onSelect(project.id)}
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
              <AppText variant="body">{project.name ?? ''}</AppText>
            </Pressable>
          );
        })}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  list: {
    gap: 6,
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
