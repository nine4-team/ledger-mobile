import { useEffect, useState } from 'react';
import { Dimensions, Platform } from 'react-native';

export type GridConfig = {
  columns: number;
  gap: number;
  columnWidth: number;
};

const BREAKPOINTS = {
  mobile: 0,
  tablet: 768,
  desktop: 1024,
};

/**
 * Hook to calculate responsive grid layout based on screen width.
 *
 * Returns:
 * - columns: Number of columns (2 on mobile, 3 on tablet, 4 on desktop)
 * - gap: Spacing between items
 * - columnWidth: Calculated width for each grid item
 */
export function useResponsiveGrid(
  containerPadding: number = 16,
  gap: number = 12
): GridConfig {
  const [dimensions, setDimensions] = useState(() => Dimensions.get('window'));

  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({ window }) => {
      setDimensions(window);
    });

    return () => subscription?.remove();
  }, []);

  const { width } = dimensions;
  const availableWidth = width - containerPadding * 2;

  let columns = 2; // Default for mobile
  if (width >= BREAKPOINTS.desktop) {
    columns = 4;
  } else if (width >= BREAKPOINTS.tablet) {
    columns = 3;
  }

  // On web, prefer more columns for wider screens
  if (Platform.OS === 'web' && width >= 1400) {
    columns = 5;
  }

  const totalGaps = gap * (columns - 1);
  const columnWidth = (availableWidth - totalGaps) / columns;

  return {
    columns,
    gap,
    columnWidth,
  };
}
