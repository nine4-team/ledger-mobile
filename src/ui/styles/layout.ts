import { StyleSheet } from 'react-native';

import { spacing } from '../kit';

/**
 * App-only shared layout primitives.
 *
 * TODO(ui-kit): Promote common layout primitives (row/center/screen body spacing) into ui-kit.
 */
export const layout = StyleSheet.create({
  flex1: {
    flex: 1,
  },
  center: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  rowBetween: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },

  /**
   * Common "screen body" wrapper used by multiple example tabs.
   * (Intentionally small + incremental; expand as patterns emerge.)
   */
  screenBodyTopMd: {
    flex: 1,
    paddingTop: spacing.md,
  },
});

