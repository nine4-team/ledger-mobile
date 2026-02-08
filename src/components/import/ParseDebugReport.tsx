import React, { useState } from 'react';
import { Alert, ScrollView, StyleSheet, TouchableOpacity, View } from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { AppText } from '../AppText';
import { useTheme } from '../../theme/ThemeProvider';

type ParseDebugReportProps = {
  rawText: string;
  stats: {
    pageCount: number;
    charCount: number;
    lineCount: number;
    durationMs: number;
  };
  parseResult: unknown;
};

export function ParseDebugReport({ rawText, stats, parseResult }: ParseDebugReportProps) {
  const theme = useTheme();
  const [statsExpanded, setStatsExpanded] = useState(false);
  const [rawTextExpanded, setRawTextExpanded] = useState(false);

  const handleCopyDebugJson = async () => {
    try {
      const report = {
        timestamp: new Date().toISOString(),
        stats,
        parseResult,
        rawTextPreview: rawText.slice(0, 2000),
        rawTextLength: rawText.length,
      };
      await Clipboard.setStringAsync(JSON.stringify(report, null, 2));
      Alert.alert('Copied', 'Debug JSON copied to clipboard.');
    } catch {
      Alert.alert('Error', 'Failed to copy to clipboard.');
    }
  };

  return (
    <View style={[styles.container, { borderColor: theme.colors.border }]}>
      <AppText variant="caption" style={styles.sectionTitle}>
        Debug Info
      </AppText>

      <TouchableOpacity
        onPress={() => setStatsExpanded((prev) => !prev)}
        style={styles.toggleButton}
        activeOpacity={0.7}
      >
        <AppText variant="caption" style={{ color: theme.colors.primary }}>
          {statsExpanded ? 'Hide Stats' : 'Show Stats'}
        </AppText>
      </TouchableOpacity>

      {statsExpanded && (
        <View style={styles.statsGrid}>
          <StatRow label="Pages" value={String(stats.pageCount)} theme={theme} />
          <StatRow label="Characters" value={stats.charCount.toLocaleString()} theme={theme} />
          <StatRow label="Lines" value={stats.lineCount.toLocaleString()} theme={theme} />
          <StatRow label="Duration" value={`${stats.durationMs}ms`} theme={theme} />
        </View>
      )}

      <TouchableOpacity
        onPress={() => setRawTextExpanded((prev) => !prev)}
        style={styles.toggleButton}
        activeOpacity={0.7}
      >
        <AppText variant="caption" style={{ color: theme.colors.primary }}>
          {rawTextExpanded ? 'Hide Raw Text' : 'Show Raw Text'}
        </AppText>
      </TouchableOpacity>

      {rawTextExpanded && (
        <ScrollView
          style={[styles.rawTextScroll, { backgroundColor: theme.colors.background, borderColor: theme.colors.border }]}
          nestedScrollEnabled
        >
          <AppText variant="caption" style={styles.rawText}>
            {rawText || '(empty)'}
          </AppText>
        </ScrollView>
      )}

      <TouchableOpacity
        onPress={handleCopyDebugJson}
        style={[styles.copyButton, { backgroundColor: theme.colors.primary }]}
        activeOpacity={0.7}
      >
        <AppText variant="body" style={styles.copyButtonText}>
          Copy Debug JSON
        </AppText>
      </TouchableOpacity>
    </View>
  );
}

type StatRowProps = {
  label: string;
  value: string;
  theme: ReturnType<typeof useTheme>;
};

function StatRow({ label, value }: StatRowProps) {
  return (
    <View style={styles.statRow}>
      <AppText variant="caption">{label}</AppText>
      <AppText variant="caption" style={styles.statValue}>
        {value}
      </AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderTopWidth: 1,
    paddingTop: 12,
    marginTop: 16,
    gap: 8,
  },
  sectionTitle: {
    fontWeight: '600',
  },
  toggleButton: {
    paddingVertical: 4,
  },
  statsGrid: {
    gap: 4,
    paddingLeft: 8,
  },
  statRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  statValue: {
    fontWeight: '600',
  },
  rawTextScroll: {
    maxHeight: 200,
    borderWidth: 1,
    borderRadius: 8,
    padding: 8,
  },
  rawText: {
    fontFamily: 'monospace',
    fontSize: 11,
  },
  copyButton: {
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 4,
  },
  copyButtonText: {
    color: '#FFFFFF',
    fontWeight: '600',
  },
});
